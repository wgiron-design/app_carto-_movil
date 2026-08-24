from pydantic import BaseModel, EmailStr, Field

class UpdateEmailRequest(BaseModel):
    new_email: EmailStr

class UpdatePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=5)
    confirm_password: str = Field(..., min_length=5)
