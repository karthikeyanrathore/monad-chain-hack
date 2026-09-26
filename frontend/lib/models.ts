export interface Model {
  id: "1B" | "3B"; // model size the Inference Service routes on
  name: string;
}

export const MODELS: Model[] = [
  { id: "1B", name: "llama 1B" },
  { id: "3B", name: "llama 3B" },
];
