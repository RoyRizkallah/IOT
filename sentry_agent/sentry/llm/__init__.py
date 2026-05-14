"""LLM provider abstraction. Today: Ollama. Tomorrow: anything OpenAI-shaped."""

from .base import ChatMessage, ChatResponse, LLMClient, ToolCall
from .ollama import OllamaClient

__all__ = ["ChatMessage", "ChatResponse", "LLMClient", "OllamaClient", "ToolCall"]
