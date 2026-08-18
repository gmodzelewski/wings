"""Plain calculator used by the LangGraph @tool wrapper.

Kept free of langchain so unit tests can import it on a laptop without the
workbench venv. Llama 3.2 3B omits b on sqrt; b must stay optional.
"""

from __future__ import annotations

from typing import Optional


def run_calculator(operation: str, a: float, b: Optional[float] = None) -> str:
    """Execute one calculator op. For sqrt, pass only a."""
    import math

    if operation == "sqrt":
        return f"sqrt({a}) = {math.sqrt(a)}"
    if b is None:
        return f"Error: {operation} requires two numbers a and b"
    ops = {
        "add": lambda x, y: x + y,
        "subtract": lambda x, y: x - y,
        "multiply": lambda x, y: x * y,
        "divide": lambda x, y: x / y if y != 0 else "Error: divide by zero",
        "power": lambda x, y: x**y,
    }
    if operation not in ops:
        return (
            f"Error: Unknown operation '{operation}'. "
            "Use: add, subtract, multiply, divide, sqrt, power"
        )
    result = ops[operation](a, b)
    if isinstance(result, str):
        return result
    return f"Result: {result}"
