from pypdf import PdfReader

reader = PdfReader("book1.pdf")
outline = reader.outline

items = []

def walk(nodes, level=0):
    for n in nodes:
        if isinstance(n, list):
            walk(n, level+1)
        else:
            try:
                title = n.title
            except Exception:
                title = str(n)
            try:
                page = reader.get_destination_page_number(n) + 1  # 1-based
            except Exception:
                page = None
            items.append((level, title, page))

walk(outline)

keywords = [
    "likelihood",
    "maximum likelihood",
    "log-likelihood",
    "cross-entropy",
    "linear regression",
    "logistic regression",
    "loss",
    "estimation",
    "empirical risk",
]

print("=== Outline (first entries) ===")
for level, title, page in items[:120]:
    indent = "  " * level
    p = page if page is not None else "?"
    print(f"{indent}- p{p}: {title}")

print("\n=== Matches ===")
for level, title, page in items:
    t = title.lower()
    if any(k in t for k in keywords):
        indent = "  " * level
        p = page if page is not None else "?"
        print(f"{indent}- p{p}: {title}")
