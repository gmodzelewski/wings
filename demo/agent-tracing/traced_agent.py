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


@dataclass
class AgentConfig:
    """Configuration for the LangChain agent."""

    model: str = "llama-32-3b-instruct"
    base_url: str = "http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1"
    api_key: str = ""
    temperature: float = 0.0
    max_tokens: int = 256


def create_llm(config: AgentConfig) -> ChatOpenAI:
    """Create ChatOpenAI instance with the in-cluster vLLM endpoint."""
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
    return AgentConfig(
        model=os.environ.get("MAAS_MODEL", "llama-32-3b-instruct"),
        base_url=os.environ.get(
            "MAAS_BASE_URL",
            "http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1",
        ),
        api_key=os.environ.get("MAAS_API_KEY", "unused"),
        temperature=0.0,
        max_tokens=int(os.environ.get("MAAS_MAX_TOKENS", "256")),
    )
