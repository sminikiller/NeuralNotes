"""Generate a valid, sparse large PDF fixture; requires reportlab and pypdf.

The large unused stream tests byte transport, not worst-case scanned-image decode.
Output stays under .verification and is never included in the app ZIP.
"""
from pathlib import Path
import argparse
import re
import shutil
import uuid
from reportlab.pdfgen import canvas
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]


def create(destination, pages=1500, size_mib=700):
    if destination.exists():
        raise FileExistsError(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    base = destination.parent / ('.base-' + str(uuid.uuid4()) + '.pdf')
    try:
        document = canvas.Canvas(str(base), pagesize=(600, 800), pageCompression=1)
        for number in range(1, pages + 1):
            document.setFont('Helvetica', 18)
            document.drawString(50, 720, 'NeuralNotes - prova PDF grande')
            document.drawString(50, 680, f'Pagina {number} di {pages}')
            document.showPage()
        document.save()
        with base.open('rb') as source:
            reader = PdfReader(source, strict=True)
            root = reader.trailer.raw_get('/Root')
            root_ref = f'{root.idnum} {root.generation} R'
            object_id = int(reader.trailer['/Size'])
            source.seek(max(0, base.stat().st_size - 1024))
            previous_xref = int(re.search(rb'startxref\s+(\d+)\s+%%EOF\s*$', source.read())[1])
            source.seek(0)
            with destination.open('xb') as output:
                shutil.copyfileobj(source, output, length=1024 * 1024)
                offset = output.tell()
                padding = max(0, size_mib * 1024 * 1024 - offset)
                output.write(f'\n{object_id} 0 obj\n<< /Type /EmbeddedFile /Length {padding} >>\nstream\n'.encode('ascii'))
                output.seek(padding, 1)  # Sparse: does not allocate a huge Python bytes object.
                output.write(b'\nendstream\nendobj\n')
                xref = output.tell()
                # Offset points at the object number, after the leading newline.
                output.write(f'xref\n0 1\n0000000000 65535 f \n{object_id} 1\n{offset + 1:010d} 00000 n \ntrailer\n<< /Size {object_id + 1} /Root {root_ref} /Prev {previous_xref} >>\nstartxref\n{xref}\n%%EOF\n'.encode('ascii'))
        with destination.open('rb') as source:
            reader = PdfReader(source, strict=True)
            assert len(reader.pages) == pages
            assert f'Pagina 1 di {pages}' in reader.pages[0].extract_text()
            assert f'Pagina {pages} di {pages}' in reader.pages[-1].extract_text()
        print(f'VALID_PDF_FIXTURE: {pages} pages, {destination.stat().st_size} bytes; first/last text verified.')
        print(destination)
    finally:
        base.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pages', type=int, default=1500)
    parser.add_argument('--size-mib', type=int, default=700)
    parser.add_argument('--output', type=Path, default=ROOT / '.verification/pdf-fixtures/large-1500.pdf')
    arguments = parser.parse_args()
    if not 1 <= arguments.pages <= 5000 or not 1 <= arguments.size_mib <= 1024:
        parser.error('Supported fixture range: 1..5000 pages, 1..1024 MiB.')
    create(arguments.output, arguments.pages, arguments.size_mib)
