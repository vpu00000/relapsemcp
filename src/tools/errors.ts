import type { ToolTextResponse } from "./factory.js";

export const NO_CLIENT_ERROR: ToolTextResponse = {
  content: [
    {
      type: "text",
      text: "Relapse has no ready Roblox session or its MCP channel is still connecting. Start the game and retry shortly.",
    },
  ],
  isError: true,
};

export const INVALID_CLIENT_ERROR: ToolTextResponse = {
  content: [
    {
      type: "text",
      text: "Invalid, inactive, or ambiguous client ID. Use list-clients for current IDs, then pass clientId or set-active-client to select a session.",
    },
  ],
  isError: true,
};
