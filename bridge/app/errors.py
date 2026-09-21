"""Shared API exceptions and HTTP error responses.

Technical details are logged on the server only. Nothing internal is ever
returned to clients.
"""

from __future__ import annotations


class ApiError(Exception):
    """Raised when the client request can be rejected with a known status."""

    status_code: int = 400
    detail: str = "Bad request"

    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


class MatlabNotConfiguredError(ApiError):
    def __init__(self, detail: str = "MATLAB screening service is not configured.") -> None:
        super().__init__(503, detail)


class MatlabExecutionError(Exception):
    """The compiled MATLAB pipeline failed while processing a request."""

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class NotFoundError(ApiError):
    def __init__(self, detail: str = "Resource not found.") -> None:
        super().__init__(404, detail)