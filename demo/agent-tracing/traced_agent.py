"""LangGraph calculator agent for WINGS3 autolog + eval.

Notebooks inline a SHOW copy of calculator and call create_agent_graph
with tools=[calculator]. This module is the library those notebooks import.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import List, Optional

from calculator_ops import run_calculator
from langchain_core.tools import BaseTool, tool
from langchain_openai import ChatOpenAI
from langgraph.prebuilt import create_react_agent
from wings3_env import (
    DEFAULT_MAAS_API_KEY,
    DEFAULT_MAAS_BASE_URL,
    DEFAULT_MAAS_MODEL,
    ensure_maas_env,
    load_wings3_secret_env,
    print_secret_key_status,
    print_workbench_env,
)

__all__ = [
    "DEFAULT_MAAS_API_KEY",
    "DEFAULT_MAAS_BASE_URL",
    "DEFAULT_MAAS_MODEL",
    "AgentConfig",
    "calculator",
    "create_agent_graph",
    "ensure_maas_env",
    "get_config_from_env",
    "load_wings3_secret_env",
    "print_secret_key_status",
    "print_workbench_env",
]


@dataclass
class AgentConfig:
    """Configuration for the LangChain agent."""

    model: str = DEFAULT_MAAS_MODEL
    base_url: str = DEFAULT_MAAS_BASE_URL
    api_key: str = DEFAULT_MAAS_API_KEY
    temperature: float = 0.0
    max_tokens: int = 256


def create_llm(config: AgentConfig) -> ChatOpenAI:
    """Create ChatOpenAI instance with the configured OpenAI-compatible endpoint."""
    return ChatOpenAI(
        model=config.model,
        api_key=config.api_key,
        base_url=config.base_url,
        temperature=config.temperature,
        max_tokens=config.max_tokens,
    )


@tool
def calculator(operation: str, a: float, b: Optional[float] = None) -> str:
    """Arithmetic: add, subtract, multiply, divide, sqrt, power.

    For sqrt, pass only a. For two-operand operations, pass a and b.
    """
    return run_calculator(operation, a, b)


DEFAULT_SYSTEM_PROMPT = """You are a helpful AI assistant with access to a calculator.

When answering questions:
1. Use the calculator for arithmetic
2. Be concise
"""


def create_agent_graph(
    config: AgentConfig,
    tools: Optional[List[BaseTool]] = None,
    system_prompt: Optional[str] = None,
):
    """Create a LangGraph ReAct agent. Defaults to calculator-only tools."""
    llm = create_llm(config)
    if tools is None:
        tools = [calculator]
    if system_prompt is None:
        system_prompt = DEFAULT_SYSTEM_PROMPT
    return create_react_agent(
        model=llm,
        tools=tools,
        prompt=system_prompt,
    )


def get_config_from_env() -> AgentConfig:
    """Load agent configuration from MAAS_* environment variables."""
    ensure_maas_env()
    return AgentConfig(
        model=os.environ["MAAS_MODEL"],
        base_url=os.environ["MAAS_BASE_URL"],
        api_key=os.environ.get("MAAS_API_KEY", DEFAULT_MAAS_API_KEY),
        temperature=0.0,
        max_tokens=int(os.environ.get("MAAS_MAX_TOKENS", "256")),
    )
