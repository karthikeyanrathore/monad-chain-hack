// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title InferenceTruth
/// @notice On-chain settlement for off-chain AI inference. Users prepay MON, providers stake MON,
///         the Inference Service records each request, and the Verification Service settles
///         spot-checked requests: PASS pays provider + verifier, FAIL slashes the provider.
/// @dev All payouts are credited to `balances` and pulled with `withdraw` (pull-payment pattern).
contract InferenceTruth is Ownable, ReentrancyGuard {
    enum Status {
        None,
        Pending,
        Passed,
        Failed,
        Settled
    }

    struct Request {
        address user;
        address provider;
        bytes32 modelId;
        uint128 price;
        uint64 createdAt;
        Status status;
        bytes32 answerHash;
    }

    uint16 public constant BPS = 10_000;

    address public inferenceService;
    address public verifier;
    uint256 public minStake;
    uint64 public challengeWindow;
    uint16 public verifierRewardBps;
    uint16 public slashBps;

    mapping(bytes32 modelId => uint256) public modelPrice;
    mapping(address account => uint256) public balances;
    mapping(address provider => uint256) public stakes;
    mapping(address provider => bytes32) public providerModel;
    mapping(address provider => uint256) public pendingCount;
    mapping(bytes32 requestId => Request) public requests;

    event ModelPriceSet(bytes32 indexed modelId, uint256 price);
    event RolesSet(address inferenceService, address verifier);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event Staked(address indexed provider, bytes32 indexed modelId, uint256 amount);
    event Unstaked(address indexed provider, uint256 amount);
    event RequestRecorded(
        bytes32 indexed requestId, address indexed user, address indexed provider, bytes32 modelId, uint256 price, bytes32 answerHash
    );
    event VerdictSubmitted(bytes32 indexed requestId, bool pass);
    event Paid(bytes32 indexed requestId, address indexed provider, uint256 amount);
    event Rewarded(bytes32 indexed requestId, address indexed verifier, uint256 amount);
    event Slashed(bytes32 indexed requestId, address indexed provider, uint256 amount);
    event Refunded(bytes32 indexed requestId, address indexed user, uint256 amount);

    error NotInferenceService();
    error NotVerifier();
    error UnknownModel();
    error ProviderNotEligible();
    error RequestExists();
    error NotPending();
    error InsufficientBalance();
    error WindowOpen();
    error HasPendingRequests();
    error ZeroAmount();
    error InvalidBps();
    error TransferFailed();

    modifier onlyInferenceService() {
        if (msg.sender != inferenceService) revert NotInferenceService();
        _;
    }

    modifier onlyVerifier() {
        if (msg.sender != verifier) revert NotVerifier();
        _;
    }

    constructor(
        address _inferenceService,
        address _verifier,
        uint256 _minStake,
        uint64 _challengeWindow,
        uint16 _verifierRewardBps,
        uint16 _slashBps,
        bytes32[] memory modelIds,
        uint256[] memory prices
    ) Ownable(msg.sender) {
        if (_verifierRewardBps > BPS || _slashBps > BPS) revert InvalidBps();
        // Prices are set here so deployment is one transaction (Monad limits low-balance senders to ~1 tx / 1.2s).
        for (uint256 i; i < modelIds.length; ++i) {
            modelPrice[modelIds[i]] = prices[i];
            emit ModelPriceSet(modelIds[i], prices[i]);
        }
        inferenceService = _inferenceService;
        verifier = _verifier;
        minStake = _minStake;
        challengeWindow = _challengeWindow;
        verifierRewardBps = _verifierRewardBps;
        slashBps = _slashBps;
        emit RolesSet(_inferenceService, _verifier);
    }

    // ---------------------------------------------------------------- admin

    function setModelPrice(bytes32 modelId, uint256 price) external onlyOwner {
        modelPrice[modelId] = price;
        emit ModelPriceSet(modelId, price);
    }

    function setRoles(address _inferenceService, address _verifier) external onlyOwner {
        inferenceService = _inferenceService;
        verifier = _verifier;
        emit RolesSet(_inferenceService, _verifier);
    }

    // ---------------------------------------------------------------- users

    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw any credited MON: unused user deposits, provider earnings, verifier rewards.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        balances[msg.sender] -= amount;
        emit Withdrawn(msg.sender, amount);
        _send(msg.sender, amount);
    }

    // ---------------------------------------------------------------- providers

    /// @notice Lock MON as collateral and register the model this provider serves.
    function stake(bytes32 modelId) external payable {
        if (msg.value == 0) revert ZeroAmount();
        if (modelPrice[modelId] == 0) revert UnknownModel();
        if (pendingCount[msg.sender] != 0 && providerModel[msg.sender] != modelId) revert HasPendingRequests();
        stakes[msg.sender] += msg.value;
        providerModel[msg.sender] = modelId;
        emit Staked(msg.sender, modelId, msg.value);
    }

    function unstake() external nonReentrant {
        if (pendingCount[msg.sender] != 0) revert HasPendingRequests();
        uint256 amount = stakes[msg.sender];
        if (amount == 0) revert ZeroAmount();
        stakes[msg.sender] = 0;
        emit Unstaked(msg.sender, amount);
        _send(msg.sender, amount);
    }

    // ---------------------------------------------------------------- Inference Service

    /// @notice Lock the model price from the user's balance for one answered request.
    function recordRequest(bytes32 requestId, address user, address provider, bytes32 modelId, bytes32 answerHash)
        external
        onlyInferenceService
    {
        uint256 price = modelPrice[modelId];
        if (price == 0) revert UnknownModel();
        if (providerModel[provider] != modelId || stakes[provider] < minStake) revert ProviderNotEligible();
        if (requests[requestId].status != Status.None) revert RequestExists();
        if (balances[user] < price) revert InsufficientBalance();

        balances[user] -= price;
        pendingCount[provider] += 1;
        requests[requestId] = Request({
            user: user,
            provider: provider,
            modelId: modelId,
            price: uint128(price),
            createdAt: uint64(block.timestamp),
            status: Status.Pending,
            answerHash: answerHash
        });
        emit RequestRecorded(requestId, user, provider, modelId, price, answerHash);
    }

    // ---------------------------------------------------------------- Verification Service

    /// @notice PASS: pay provider, reward verifier. FAIL: refund user, slash provider stake to the owner.
    function submitVerdict(bytes32 requestId, bool pass) external onlyVerifier {
        Request storage r = requests[requestId];
        if (r.status != Status.Pending) revert NotPending();
        pendingCount[r.provider] -= 1;
        emit VerdictSubmitted(requestId, pass);

        if (pass) {
            r.status = Status.Passed;
            uint256 reward = uint256(r.price) * verifierRewardBps / BPS;
            balances[msg.sender] += reward;
            balances[r.provider] += r.price - reward;
            emit Rewarded(requestId, msg.sender, reward);
            emit Paid(requestId, r.provider, r.price - reward);
        } else {
            r.status = Status.Failed;
            balances[r.user] += r.price;
            uint256 slash = stakes[r.provider] * slashBps / BPS;
            stakes[r.provider] -= slash;
            balances[owner()] += slash;
            emit Refunded(requestId, r.user, r.price);
            emit Slashed(requestId, r.provider, slash);
        }
    }

    // ---------------------------------------------------------------- settlement

    /// @notice Pay the provider for a request that was not challenged within the window. Callable by anyone.
    function settle(bytes32 requestId) external {
        Request storage r = requests[requestId];
        if (r.status != Status.Pending) revert NotPending();
        if (block.timestamp < r.createdAt + challengeWindow) revert WindowOpen();
        r.status = Status.Settled;
        pendingCount[r.provider] -= 1;
        balances[r.provider] += r.price;
        emit Paid(requestId, r.provider, r.price);
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
