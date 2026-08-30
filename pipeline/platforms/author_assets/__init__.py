"""Author asset platform helpers."""

from .avatars import main as refresh_author_avatars


def refresh_x_profiles(*args, **kwargs):
    from .x_profiles import refresh_x_profiles as refresh

    return refresh(*args, **kwargs)

__all__ = ["refresh_author_avatars", "refresh_x_profiles"]
