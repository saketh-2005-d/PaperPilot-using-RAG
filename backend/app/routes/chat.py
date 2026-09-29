import re
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import select, text

from ..db import get_db
from ..models import Document, Chunk, Message
from ..schemas import ChatIn, ChatOut, Citation, MessageOut
from ..auth import get_current_user
from ..llm import embed_texts, chat_with_context

router = APIRouter()


_GREETING_PATTERNS = {
    "hi", "hii", "hiii", "hello", "helo", "hey", "heya", "hola", "yo",
    "thanks", "thank you", "ty", "thx", "cheers",
    "who are you", "what are you", "what can you do", "what do you do",
    "help", "?", "ok", "okay", "cool", "nice", "great",
    "good morning", "good evening", "good afternoon", "gm", "gn",
}


def _is_smalltalk(message: str) -> bool:
    """Cheap heuristic: short greeting/small-talk messages skip retrieval."""
    m = re.sub(r"[^\w\s]", "", message.strip().lower()).strip()
    if not m:
        return True
    if len(m.split()) > 4:
        return False
    return m in _GREETING_PATTERNS


@router.get("/{doc_id}/messages", response_model=list[MessageOut])
def list_messages(doc_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
    doc = db.get(Document, doc_id)
    if not doc or doc.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    rows = db.execute(
        select(Message)
        .where(Message.user_id == user.id, Message.document_id == doc_id)
        .order_by(Message.created_at.asc())
    ).scalars().all()
    return [
        MessageOut(
            id=m.id,
            role=m.role,
            content=m.content,
            citations=[Citation(**c) for c in (m.citations_json or [])],
            created_at=m.created_at,
        )
        for m in rows
    ]


@router.post("/{doc_id}", response_model=ChatOut)
def chat_in_doc(
    doc_id: int,
    payload: ChatIn,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    doc = db.get(Document, doc_id)
    if not doc or doc.user_id != user.id:
        raise HTTPException(status_code=404, detail="Not found")
    if doc.status != "ready":
        raise HTTPException(status_code=409, detail=f"Document not ready (status: {doc.status})")

    q = payload.message.strip()
    if not q:
        raise HTTPException(status_code=400, detail="Empty message")

    smalltalk = _is_smalltalk(q)

    if smalltalk:
        contexts = []
    else:
        q_embed = embed_texts([q])[0]
        rows = db.execute(
            text("""
                SELECT id, page_start, page_end, section, content
                FROM chunks
                WHERE document_id = :doc_id
                ORDER BY embedding <=> CAST(:emb AS vector)
                LIMIT 6
            """),
            {"doc_id": doc_id, "emb": str(q_embed)},
        ).mappings().all()
        contexts = [dict(r) for r in rows]

    history_rows = db.execute(
        select(Message)
        .where(Message.user_id == user.id, Message.document_id == doc_id)
        .order_by(Message.created_at.asc())
    ).scalars().all()
    history = [{"role": m.role, "content": m.content} for m in history_rows]

    answer = chat_with_context(
        history,
        q,
        contexts,
        title=doc.title,
        tldr=doc.summary_tldr,
    )

    citations = [
        Citation(section=c["section"], page_start=c["page_start"], page_end=c["page_end"])
        for c in contexts
    ]

    db.add(Message(
        user_id=user.id, document_id=doc_id, role="user", content=q, citations_json=[],
    ))
    db.add(Message(
        user_id=user.id, document_id=doc_id, role="assistant", content=answer,
        citations_json=[c.model_dump() for c in citations],
    ))
    db.commit()

    return ChatOut(answer=answer, citations=citations)
