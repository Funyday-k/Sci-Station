export const agent = {
  id: "sci-station",
  name: "Sci-Station",
  config: "~/.config/sci-station/connection.json",
  format: "json",
  model: "model",
  ua: ["SciStation"],
};

export function connect({ gateway }) {
  if (!/^http:\/\/(127\.0\.0\.1|localhost):[0-9]+\/v1\/?$/i.test(gateway.v1)) {
    throw new Error("Sci-Station requires a local HTTP gateway.");
  }
  if (gateway.key !== "magpie-" + agent.id) {
    throw new Error("Select the local Magpie gateway for Sci-Station.");
  }
  return { baseURL: gateway.v1 };
}
