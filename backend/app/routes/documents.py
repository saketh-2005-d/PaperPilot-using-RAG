from io import BytesIO
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import select
from pypdf import PdfReader

from ..db import get_db, SessionLocal
from ..models import Document, Chunk, Message
from ..schemas import DocumentOut, DocumentListItem
from ..auth import get_current_user
from ..config import settings
from ..storage import s3_key_for, upload_bytes, delete_key, presigned_get
from ..pdf_proc import extract_pages, chunk_pages
from ..llm import embed_texts, summarize_section, summarize_tldr

router = APIRouter()


def _to_out(doc: Document) -> DocumentOut:
    return DocumentOut(
        id=doc.id,
        title=doc.title,
        page_count=doc.page_count,
        status=doc.status,
        summary_tldr=doc.summary_tldr,
        sections=doc.sections_json or [],
        error=doc.error,
        created_at=doc.created_at,
    )


def _process_document(doc_id: int):
    db = SessionLocal()
    try:
        doc = db.get(Document, doc_id)
        if not doc:
            return
        try:
            doc.status = "extracting"
            db.commit()

            from ..storage import _s3
            obj = _s3.get_object(Bucket=settings.S3_BUCKET, Key=doc.s3_key)
            data = obj["Body"].read()

            reader = PdfReader(BytesIO(data))
            page_count = len(reader.pages)
            doc.page_count = page_count

            pages = extract_pages(data)
            sections = chunk_pages(pages, pages_per_section=5)
            if not sections or sum(len(s["content"]) for s in sections) < 50:
                doc.status = "failed"
                doc.error = "This PDF appears to be a scanned image. Text extraction is not supported yet."
                db.commit()
                return

            doc.status = "embedding"
            db.commit()

            embeddings = embed_texts([s["content"][:6000] for s in sections])
            for s, emb in zip(sections, embeddings):
                db.add(Chunk(
                    document_id=doc.id,
                    page_start=s["page_start"],
                    page_end=s["page_end"],
                    section=s["section"],
                    content=s["content"],
                    embedding=emb,
                ))
            db.commit()

            doc.status = "summarizing"
            db.commit()

            section_summaries = []
            sections_out = []
            for s in sections:
                summ = summarize_section(s["content"])
                section_summaries.append(summ)
                sections_out.append({
                    "section": s["section"],
                    "page_start": s["page_start"],
                    "page_end": s["page_end"],
                    "summary": summ,
                })
            tldr = summarize_tldr(section_summaries)

            doc.summary_tldr = tldr
            doc.sections_json = sections_out
            doc.status = "ready"
            db.commit()
        except Exception as e:
            doc.status = "failed"
            doc.error = str(e)[:1000]
            db.commit()
    finally:
        db.close()


@router.post("", response_model=DocumentOut)
def upload_document(
    background: BackgroundTasks,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    raw = file.file.read()
    if len(raw) > settings.MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 50 MB)")
    if not raw.startswith(b"%PDF-"):
        raise HTTPException(status_code=422, detail="File is not a valid PDF")

    title = (file.filename or "untitled.pdf").rsplit("/", 1)[-1]

    doc = Document(
        user_id=user.id,
        title=title,
        s3_key="pending",
        status="uploading",
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)

    key = s3_key_for(user.id, doc.id, title)
    upload_bytes(key, raw, content_type="application/pdf")
    doc.s3_key = key
    db.commit()
    db.refresh(doc)

    background.add_task(_process_document, doc.id)
    return _to_out(doc)


@router.get("", response_model=list[DocumentListItem])
def list_documents(db: Session = Depends(get_db), user=Depends(get_current_user)):
    rows = db.execute(
        select(Document).where(Document.user_id == user.id).order_by(Document.created_at.desc())
    ).scalars().all()
    return [DocumentListItem.model_validate(d) for d in rows]


@router.get("/{doc_id}", response_model=DocumentOut)
def get_document(doc_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
    doc = db.get(Document, doc_id)
    if not doc or doc.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    return _to_out(doc)


@router.get("/{doc_id}/pdf-url")
def get_pdf_url(doc_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
    doc = db.get(Document, doc_id)
    if not doc or doc.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    return {"url": presigned_get(doc.s3_key, expires=900)}


@router.delete("/{doc_id}")
def delete_document(doc_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
    doc = db.get(Document, doc_id)
    if not doc or doc.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    key = doc.s3_key
    db.delete(doc)
    db.commit()
    if key and key != "pending":
        delete_key(key)
    return {"ok": True}
