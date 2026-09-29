from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_MINUTES: int = 10080

    AWS_ACCESS_KEY_ID: str
    AWS_SECRET_ACCESS_KEY: str
    AWS_REGION: str = "ap-south-1"
    S3_BUCKET: str

    OPENAI_API_KEY: str
    OPENAI_MODEL: str = "gpt-4o-mini"
    OPENAI_EMBED_MODEL: str = "text-embedding-3-small"
    EMBED_DIM: int = 1536

    GOOGLE_OAUTH_CLIENT_IDS: str = ""

    MAX_UPLOAD_BYTES: int = 52428800

    @property
    def google_audiences(self) -> list[str]:
        return [a.strip() for a in self.GOOGLE_OAUTH_CLIENT_IDS.split(",") if a.strip()]


settings = Settings()
