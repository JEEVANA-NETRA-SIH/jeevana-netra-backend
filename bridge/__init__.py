"""Jeevana Netra HTTP bridge package.

The bridge exposes the compiled MATLAB screening/explanation/report pipeline
as a real HTTP API. MATLAB functions are never reimplemented here; the bridge
only marshals HTTP <-> JSON <-> compiled MATLAB.
"""

__version__ = "1.0.0"