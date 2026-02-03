import pydantic
import datetime

class AutoHPL_Results(pydantic.BaseModel):
    TV: str
    N: int = pydantic.Field(gt=0)
    NB: int = pydantic.Field(gt=0)
    P: int = pydantic.Field(gt=0)
    Q: int = pydantic.Field(gt=0)
    Time: float = pydantic.Field(gt=0, allow_inf_nan=False)
    Gflops: float = pydantic.Field(gt=0, allow_inf_nan=False)
    Start_Date: datetime.datetime
    End_Date: datetime.datetime
