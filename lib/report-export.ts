/** Small server-side PDF writer with WinAnsi Portuguese text and wrapped lines. */
export function reportPdf(input:string[]){
 const clean=(s:string)=>s.replace(/[–—→]/g,'-').replace(/[^\x20-\xFF]/g,'?');
 const lines=input.flatMap(line=>{const text=clean(line);if(!text)return [''];const out:string[]=[];let rest=text;while(rest.length>92){let at=rest.lastIndexOf(' ',92);if(at<20)at=92;out.push(rest.slice(0,at));rest=rest.slice(at).trimStart();}out.push(rest);return out;});
 const escape=(s:string)=>s.replaceAll('\\','\\\\').replaceAll('(','\\(').replaceAll(')','\\)');
 const pages=Array.from({length:Math.max(1,Math.ceil(lines.length/46))},(_,i)=>lines.slice(i*46,i*46+46));
 const objects:string[]=['<< /Type /Catalog /Pages 2 0 R >>',''];
 for(let i=0;i<pages.length;i++){const body=`BT /F1 10 Tf 40 790 Td ${pages[i].map((line,j)=>`${j?'0 -15 Td ':''}(${escape(line)}) Tj`).join(' ')} ET BT /F1 9 Tf 40 30 Td (DeliGo Triunfal - ${i+1}/${pages.length}) Tj ET`;objects.push('',`<< /Length ${Buffer.byteLength(body,'latin1')} >>\nstream\n${body}\nendstream`);}
 const font=objects.length+1;objects.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
 objects[1]=`<< /Type /Pages /Kids [${pages.map((_,i)=>`${3+i*2} 0 R`).join(' ')}] /Count ${pages.length} >>`;
 pages.forEach((_,i)=>{objects[2+i*2]=`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 ${font} 0 R >> >> /Contents ${4+i*2} 0 R >>`;});
 let output='%PDF-1.4\n';const offsets=[0];objects.forEach((o,i)=>{offsets.push(Buffer.byteLength(output,'latin1'));output+=`${i+1} 0 obj\n${o}\nendobj\n`;});const xref=Buffer.byteLength(output,'latin1');output+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n${offsets.slice(1).map(x=>`${String(x).padStart(10,'0')} 00000 n `).join('\n')}\ntrailer << /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
 return new Uint8Array(Buffer.from(output,'latin1'));
}
