"""Fail publication before required iOS fields can break decoding."""
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class Profile(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)
    id: str = Field(min_length=1)
    name: str
    handle: str
    platform: Literal["X"]
    score: float
    scoreChange: float
    specialty: str
    horizon: str


class View(BaseModel):
    model_config = ConfigDict(extra="allow", allow_inf_nan=False)
    id: UUID
    ticker: str = Field(min_length=1)
    companyName: str
    authorId: str = Field(min_length=1)
    authorName: str
    platform: Literal["X"]
    score: float
    platformPercentile: float = Field(ge=0, le=1)
    direction: Literal["bullish", "bearish", "neutral", "mixed"]
    lifecycle: Literal["new", "strengthened", "weakened", "reversed", "closed", "invalidated"]
    horizon: str
    thesis: str
    publishedAt: datetime

    @field_validator("publishedAt")
    @classmethod
    def aware_date(cls, value):
        if value.tzinfo is None:
            raise ValueError("publishedAt requires a timezone")
        return value
