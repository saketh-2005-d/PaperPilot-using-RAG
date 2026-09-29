from io import BytesIO
from pypdf import PdfReader


def extract_pages(data: bytes) -> list[str]:
    reader = PdfReader(BytesIO(data))
    pages = []
    for p in reader.pages:
        try:
            pages.append(p.extract_text() or "")
        except Exception:
            pages.append("")
    return pages


def chunk_pages(pages: list[str], pages_per_section: int = 5) -> list[dict]:
    """Group pages into sections of N pages each."""
    sections = []
    for i in range(0, len(pages), pages_per_section):
        page_start = i + 1
        page_end = min(i + pages_per_section, len(pages))
        text = "\n\n".join(pages[i:i + pages_per_section]).strip()
        if not text:
            continue
        sections.append({
            "page_start": page_start,
            "page_end": page_end,
            "section": f"Pages {page_start}–{page_end}",
            "content": text,
        })
    return sections
