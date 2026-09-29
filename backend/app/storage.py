import boto3
from botocore.config import Config
from .config import settings

_s3 = boto3.client(
    "s3",
    aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
    aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
    region_name=settings.AWS_REGION,
    endpoint_url=f"https://s3.{settings.AWS_REGION}.amazonaws.com",
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)


def s3_key_for(user_id: int, doc_id: int, filename: str) -> str:
    safe = filename.replace("/", "_")
    return f"users/{user_id}/{doc_id}/{safe}"


def upload_bytes(key: str, data: bytes, content_type: str = "application/pdf") -> None:
    _s3.put_object(
        Bucket=settings.S3_BUCKET,
        Key=key,
        Body=data,
        ContentType=content_type,
    )


def delete_key(key: str) -> None:
    try:
        _s3.delete_object(Bucket=settings.S3_BUCKET, Key=key)
    except Exception:
        pass


def delete_prefix(prefix: str) -> None:
    """Delete every object under a prefix (for full-account cleanup)."""
    paginator = _s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=settings.S3_BUCKET, Prefix=prefix):
        keys = [{"Key": o["Key"]} for o in page.get("Contents", [])]
        if not keys:
            continue
        for i in range(0, len(keys), 1000):
            batch = keys[i:i + 1000]
            try:
                _s3.delete_objects(
                    Bucket=settings.S3_BUCKET,
                    Delete={"Objects": batch, "Quiet": True},
                )
            except Exception:
                pass


def presigned_get(key: str, expires: int = 600) -> str:
    return _s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.S3_BUCKET, "Key": key},
        ExpiresIn=expires,
    )
