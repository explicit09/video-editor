"""Local-first automated evaluation system for VideoEditor."""

from .config import EvalConfig, load_config
from .corpus import CorpusManager, SandboxStager
from .mcp import MCPClient
from .models import (
    CorpusItem,
    CorpusManifest,
    FinalDecision,
    JudgeResult,
    JudgeTask,
    RunRecord,
    ValidatorResult,
    WorkflowSpec,
)
from .reporting import (
    FAILURE_CATEGORY_EXPECTED,
    FAILURE_CATEGORY_INFRASTRUCTURE,
    FAILURE_CATEGORY_MIXED,
    FAILURE_CATEGORY_PRODUCT,
    FAILURE_CATEGORY_UNKNOWN,
    classify_run_failure,
    workflow_policy_summary,
)
from .storage import EvalStore

__all__ = [
    "CorpusItem",
    "CorpusManifest",
    "CorpusManager",
    "EvalConfig",
    "EvalStore",
    "FAILURE_CATEGORY_EXPECTED",
    "FAILURE_CATEGORY_INFRASTRUCTURE",
    "FAILURE_CATEGORY_MIXED",
    "FAILURE_CATEGORY_PRODUCT",
    "FAILURE_CATEGORY_UNKNOWN",
    "FinalDecision",
    "JudgeResult",
    "JudgeTask",
    "MCPClient",
    "RunRecord",
    "SandboxStager",
    "ValidatorResult",
    "WorkflowSpec",
    "classify_run_failure",
    "load_config",
    "workflow_policy_summary",
]


def __getattr__(name: str):
    if name == "EvaluationRunner":
        from .runner import EvaluationRunner

        return EvaluationRunner
    if name == "EvalHTTPServer":
        from .service import EvalHTTPServer

        return EvalHTTPServer
    raise AttributeError(name)
