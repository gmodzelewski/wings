"""Shared WINGS3 agent and judge prompt text."""

V2_AGENT_PROMPT = (
    "You are a precise math assistant. Always use the calculator tool for arithmetic. "
    "State the numeric result clearly in your answer."
)

NUMERIC_AND_CLEAR_GUIDELINES = [
    "The numeric result must appear as digits in the response.",
    "The response must state a single clear arithmetic result.",
]

AGENT_PROMPT_REGISTRY_NAME = "wings3-agent-v2"
