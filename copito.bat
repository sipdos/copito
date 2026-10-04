<# :
@echo off
setlocal EnableExtensions
title Copito
set "COPIITO_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=$env:COPIITO_SELF; $L=Get-Content -LiteralPath $f; $i=-1; for($k=0;$k -lt $L.Count;$k++){ if($L[$k].Trim() -eq '#>'){ $i=$k; break } }; if($i -lt 0){ Write-Error 'no powershell section'; exit 1 }; $ps=($L[($i+1)..($L.Count-1)] -join [Environment]::NewLine); Invoke-Expression $ps"
if errorlevel 1 pause
endlocal
exit /b
#>
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$ROOT=$PSScriptRoot; if(-not $ROOT){ $ROOT=Split-Path -Parent $env:COPIITO_SELF }
$WEB_PORT=8080; $API_PORT=20666
$script:FAILED=$false

$CsharpCode=@'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.IO.Compression;
using System.Diagnostics;
using System.Web.Script.Serialization;
namespace Copito {
  public class Item { public string Type; public string Text; public string Model; public object Usage; public string Error; }
  public class Job { public string Id; public Dictionary<string,object> Payload; public ConcurrentQueue<Item> Out=new ConcurrentQueue<Item>(); public ManualResetEventSlim Evt=new ManualResetEventSlim(false); }
  public class JobLog { public StringBuilder Sb=new StringBuilder(); public object Lk=new object(); public volatile bool Done=false; public string Result="";
    public void Line(string s){ lock(Lk){ Sb.Append(s).Append("\n"); } }
    public string Snap(){ lock(Lk){ return Sb.ToString(); } } }
  public static class Server {
    static TcpListener _web,_api; static string _root,_self;
    static readonly ConcurrentDictionary<string,Job> _jobs=new ConcurrentDictionary<string,Job>();
    static readonly ConcurrentQueue<string> _pollQ=new ConcurrentQueue<string>();
    static readonly ManualResetEventSlim _pollEvt=new ManualResetEventSlim(false);
    static volatile bool _enabled=false; static string _apiKey=""; static string _model="copito-local";
    static readonly ConcurrentDictionary<string,JobLog> _ajobs=new ConcurrentDictionary<string,JobLog>();
    static readonly JavaScriptSerializer JS=NewJs();
    static JavaScriptSerializer NewJs(){ JavaScriptSerializer j=new JavaScriptSerializer(); j.MaxJsonLength=int.MaxValue; j.RecursionLimit=1000; return j; }
    const int POLL_WAIT=25000; const int JOB_WAIT=300000;
    static readonly string[] LOOP=new string[]{"127.0.0.1","::1","localhost","[::1]","0:0:0:0:0:0:0:1"};
    static readonly string WLLAMA_VER="3.6.1";
    static readonly string BW361="https://cdn.jsdelivr.net/npm/@wllama/wllama@3.6.1/esm/";
    static string WBase(){ return BW361; }
    static readonly string BV="https://copy.sh/v86/";
    static readonly string BP="https://cdn.jsdelivr.net/pyodide/v0.26.4/full/";
    static readonly string RULE_W="Copito Web 8080";
    static readonly string RULE_A="Copito Endpoint 20666";

    public static void Start(int webPort,int apiPort,string root,string self){
      _root=Path.GetFullPath(root); _self=self;
      _web=new TcpListener(IPAddress.Any,webPort); _api=new TcpListener(IPAddress.Any,apiPort);
      try{ _web.Start(); }catch(Exception e){ throw new Exception("No se pudo abrir 0.0.0.0:"+webPort+" -> "+e.Message); }
      try{ _api.Start(); }catch(Exception e){ _web.Stop(); throw new Exception("No se pudo abrir 0.0.0.0:"+apiPort+" -> "+e.Message); }
      Thread t1=new Thread(new ThreadStart(delegate{ AcceptLoop(_web,HandleWeb); })); t1.IsBackground=false; t1.Start();
      Thread t2=new Thread(new ThreadStart(delegate{ AcceptLoop(_api,HandleApi); })); t2.IsBackground=false; t2.Start();
    }
    static void AcceptLoop(TcpListener lis,Action<TcpClient> handler){ while(true){ TcpClient c=null; try{ c=lis.AcceptTcpClient(); }catch{ break; } TcpClient cc=c; ThreadPool.QueueUserWorkItem(delegate{ try{ handler(cc); }catch{}finally{ try{cc.Close();}catch{} } }); } }
    class Req { public string Method; public string Path; public string RawPath; public Dictionary<string,string> Headers=new Dictionary<string,string>(); public string Body; }
    static Req ReadReq(NetworkStream s){
      MemoryStream hs=new MemoryStream(); byte[] b=new byte[1]; int tail=0; byte[] t4=new byte[4];
      while(true){ int n=s.Read(b,0,1); if(n<=0) break; hs.Write(b,0,1); t4[tail++]=b[0]; if(tail==4){ if(t4[0]==13&&t4[1]==10&&t4[2]==13&&t4[3]==10) break; t4[0]=t4[1];t4[1]=t4[2];t4[2]=t4[3];tail=3; } if(hs.Length>256*1024) break; }
      string head=Encoding.GetEncoding("ISO-8859-1").GetString(hs.ToArray()); int idx=head.IndexOf("\r\n\r\n");
      string hp=idx>=0?head.Substring(0,idx):head; string[] lines=hp.Split(new string[]{"\r\n"},StringSplitOptions.None);
      Req r=new Req(); if(lines.Length>0){ string[] f=lines[0].Split(' '); r.Method=f[0]; r.RawPath=f.Length>1?f[1]:"/"; r.Path=r.RawPath.Split('?')[0]; }
      for(int i=1;i<lines.Length;i++){ int c=lines[i].IndexOf(':'); if(c>0) r.Headers[lines[i].Substring(0,c).Trim().ToLower()]=lines[i].Substring(c+1).Trim(); }
      int cl=0; if(r.Headers.ContainsKey("content-length")) int.TryParse(r.Headers["content-length"],out cl);
      if(cl>0){ byte[] body=new byte[cl]; int off=0; while(off<cl){ int n=s.Read(body,off,cl-off); if(n<=0) break; off+=n; } r.Body=Encoding.UTF8.GetString(body,0,off); } else r.Body="";
      return r;
    }
    static string QueryVal(Req r,string key){ int i=r.RawPath.IndexOf('?'); if(i<0) return null; foreach(string kv in r.RawPath.Substring(i+1).Split('&')){ int e=kv.IndexOf('='); if(e>0 && kv.Substring(0,e)==key) return Uri.UnescapeDataString(kv.Substring(e+1)); } return null; }
    static void Cors(StringBuilder sb){ sb.Append("Cross-Origin-Opener-Policy: same-origin\r\n"); sb.Append("Cross-Origin-Embedder-Policy: credentialless\r\n"); sb.Append("Access-Control-Allow-Origin: *\r\n"); sb.Append("Access-Control-Allow-Methods: GET,POST,OPTIONS\r\n"); sb.Append("Access-Control-Allow-Headers: Content-Type,Authorization,x-api-key,anthropic-version\r\n"); sb.Append("Access-Control-Max-Age: 86400\r\n"); }
    static void SendHead(NetworkStream s,int code,string status,Dictionary<string,string> ex,bool close){ StringBuilder sb=new StringBuilder(); sb.Append("HTTP/1.1 ").Append(code).Append(' ').Append(status).Append("\r\n"); Cors(sb); if(close) sb.Append("Connection: close\r\n"); if(ex!=null) foreach(KeyValuePair<string,string> kv in ex) sb.Append(kv.Key).Append(": ").Append(kv.Value).Append("\r\n"); sb.Append("\r\n"); byte[] hb=Encoding.ASCII.GetBytes(sb.ToString()); s.Write(hb,0,hb.Length); }
    static void SendJson(NetworkStream s,int code,string status,object o){ string body=JS.Serialize(o); byte[] bb=Encoding.UTF8.GetBytes(body); Dictionary<string,string> ex=new Dictionary<string,string>(); ex["Content-Type"]="application/json"; ex["Content-Length"]=bb.Length.ToString(); SendHead(s,code,status,ex,true); s.Write(bb,0,bb.Length); s.Flush(); }
    static void SendEmpty(NetworkStream s,int code,string status){ Dictionary<string,string> ex=new Dictionary<string,string>(); ex["Content-Length"]="0"; SendHead(s,code,status,ex,true); s.Flush(); }
    static void WriteSse(NetworkStream s,object o){ byte[] bb=Encoding.UTF8.GetBytes("data: "+JS.Serialize(o)+"\n\n"); s.Write(bb,0,bb.Length); s.Flush(); }
    static bool IsInternal(TcpClient c){ try{ string ip=((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString(); foreach(string l in LOOP) if(ip==l) return true; }catch{} return false; }
    static bool AuthOk(Req r){ if(string.IsNullOrEmpty(_apiKey)) return true; string x=r.Headers.ContainsKey("x-api-key")?r.Headers["x-api-key"]:""; string a=r.Headers.ContainsKey("authorization")?r.Headers["authorization"]:""; return x==_apiKey || a==("Bearer "+_apiKey) || a.ToLower()==("bearer "+_apiKey.ToLower()); }
    static string GStr(Dictionary<string,object> d,string k){ object v; if(d!=null&&d.TryGetValue(k,out v)){ string s=v as string; if(s!=null) return s; } return null; }
    static object GObj(Dictionary<string,object> d,string k){ object v; if(d!=null&&d.TryGetValue(k,out v)) return v; return null; }
    static bool GBool(Dictionary<string,object> d,string k){ object v; if(d!=null&&d.TryGetValue(k,out v)){ bool? b=v as bool?; if(b.HasValue) return b.Value; } return false; }
    static Dictionary<string,object> ErrObj(string msg){ return new Dictionary<string,object>{{"error",new Dictionary<string,object>{{"message",msg}}}}; }

    static string RunCapture(string file,string args){
      try{ ProcessStartInfo psi=new ProcessStartInfo(file,args); psi.UseShellExecute=false; psi.CreateNoWindow=true; psi.RedirectStandardOutput=true; psi.RedirectStandardError=true;
        using(Process p=Process.Start(psi)){ string o=p.StandardOutput.ReadToEnd(); string er=p.StandardError.ReadToEnd(); p.WaitForExit(); return o+er+"\n[exit "+p.ExitCode+"]"; } }
      catch(Exception ex){ return "[error] "+ex.Message; }
    }
    static string RunElevated(string file,string args){
      try{ ProcessStartInfo psi=new ProcessStartInfo(file,args); psi.UseShellExecute=true; psi.Verb="runas"; psi.WindowStyle=ProcessWindowStyle.Hidden;
        using(Process p=Process.Start(psi)){ p.WaitForExit(); return "[elevated exit "+p.ExitCode+"]"; } }
      catch(Exception ex){ return "[UAC cancelado o fallo] "+ex.Message; }
    }
    static bool ValidWasm(string p){
      try{ if(!File.Exists(p)) return false; FileInfo fi=new FileInfo(p); if(fi.Length<1000000) return false;
        using(var fs=File.OpenRead(p)){ byte[] b=new byte[4]; fs.Read(b,0,4); return b[0]==0&&b[1]==0x61&&b[2]==0x73&&b[3]==0x6D; } }
      catch{ return false; }
    }
    // Un index.js de wllama >= 3.x trae WebGPU. El 2.x NO, y ademas el worker forcea
    // n_gpu_layers:0, asi que la GPU queda anulada y los tok/s se desploman.
    static bool HasWebGPU(string idx){
      try{ if(!File.Exists(idx)) return false; string t=File.ReadAllText(idx);
        return t.Contains("requestAdapter")||t.Contains("navigator.gpu")||t.Contains("GPUBufferUsage"); }
      catch{ return false; }
    }
    static bool StaleWllama(string idx){ return File.Exists(idx) && !HasWebGPU(idx); }
    static bool DownloadFile(string url,string dest,JobLog lg){
      try{ Directory.CreateDirectory(Path.GetDirectoryName(dest));
        HttpWebRequest req=(HttpWebRequest)WebRequest.Create(url); req.Timeout=240000; req.ReadWriteTimeout=240000; req.UserAgent="copito/1.0";
        using(WebResponse resp=req.GetResponse()){ long total=resp.ContentLength; long got=0; int lastPct=-1;
          using(Stream rs=resp.GetResponseStream()){ using(FileStream fs=new FileStream(dest,FileMode.Create,FileAccess.Write)){
            byte[] buf=new byte[65536]; int n;
            while((n=rs.Read(buf,0,buf.Length))>0){ fs.Write(buf,0,n); got+=n; if(total>0){ int pct=(int)(got*100/total); if(pct/5!=lastPct/5){ lastPct=pct; lg.Line("  "+pct+"% ("+(got/1048576)+"MB)"); } } }
          } } }
        lg.Line("  OK "+dest); return true; }
      catch(Exception e){ lg.Line("  X "+e.Message); try{ File.Delete(dest);}catch{} return false; }
    }
static void RunSetup(string which,JobLog lg){ // <<< CAMBIO: version configurable + sin copia-basura
  bool all=(which==null||which==""||which=="all");
  if(all||which=="wllama"){
    lg.Line("[wllama v"+WLLAMA_VER+"] usa ./wllama/; repara si falta");
    string b=WBase();
    string idx=Path.Combine(_root,"wllama","index.js");
    // Si el index.js existe pero es un 2.x (sin WebGPU), se REBAJA: antes el "if(!File.Exists)"
    // lo daba por bueno para siempre y dejaba la GPU anulada para siempre.
    if(StaleWllama(idx)){
      lg.Line("  ! encontrado wllama 2.x sin WebGPU en ./wllama/index.js -> se reemplaza por v"+WLLAMA_VER);
      try{ File.Delete(idx); }catch{}
      foreach(string old in new string[]{"wasm/wllama.wasm","multi-thread/wllama.wasm","single-thread/wllama.wasm","wllama.wasm"}){
        try{ File.Delete(Path.Combine(_root,"wllama",old.Replace('/','\\'))); }catch{}
      }
    }
    if(!File.Exists(idx)) DownloadFile(b+"index.js",idx,lg);
    string w1=Path.Combine(_root,"wllama","wasm","wllama.wasm");
    if(!ValidWasm(w1)) DownloadFile(b+"wasm/wllama.wasm",w1,lg);
    // multi-thread: descargar de SU ruta real. Si 404 (2.3.1 puede no tenerlo), NO copiar el generico encima.
    string mt=Path.Combine(_root,"wllama","multi-thread","wllama.wasm");
    if(!ValidWasm(mt)){
      if(!DownloadFile(b+"multi-thread/wllama.wasm",mt,lg)) lg.Line("  ! multi-thread no existe en v"+WLLAMA_VER+" (ok para CPU single)");
    }
    // single-thread: ruta real (antes el .bat bajaba 'wllama.wasm' raiz por typo -> bug arreglado)
    string st=Path.Combine(_root,"wllama","single-thread","wllama.wasm");
    if(!ValidWasm(st)){
      if(!DownloadFile(b+"single-thread/wllama.wasm",st,lg)) lg.Line("  ! single-thread no existe en v"+WLLAMA_VER);
    }
    // Carpeta VERSIONADA ./wllama/<ver>/ : es la que index.html prefiere (WLLAMA_BASES[0]).
    // Se instala para que la app no dependa de la carpeta plana.
    string vd=Path.Combine(_root,"wllama",WLLAMA_VER);
    string vidx=Path.Combine(vd,"index.js");
    if(StaleWllama(vidx)||!File.Exists(vidx)) DownloadFile(b+"index.js",vidx,lg);
    string[] vw=new string[]{"multi-thread/wllama.wasm","single-thread/wllama.wasm","wasm/wllama.wasm"};
    foreach(string r in vw){ string vp=Path.Combine(vd,r.Replace('/','\\')); if(!ValidWasm(vp)) DownloadFile(b+r,vp,lg); }
    lg.Line("  versionado en ./wllama/"+WLLAMA_VER+"/");
  }
  if(all||which=="v86"){ lg.Line("[v86] (~100MB)");
    DownloadFile(BV+"build/libv86.js",Path.Combine(_root,"v86","libv86.js"),lg);
    DownloadFile(BV+"build/v86.wasm",Path.Combine(_root,"v86","v86.wasm"),lg);
    DownloadFile(BV+"bios/seabios.bin",Path.Combine(_root,"v86","bios","seabios.bin"),lg);
    DownloadFile(BV+"bios/vgabios.bin",Path.Combine(_root,"v86","bios","vgabios.bin"),lg);
    DownloadFile(BV+"images/buildroot.iso",Path.Combine(_root,"v86","images","buildroot.iso"),lg); }
  if(all||which=="pyodide"){ lg.Line("[pyodide]");
    DownloadFile(BP+"pyodide.js",Path.Combine(_root,"pyodide","pyodide.js"),lg);
    DownloadFile(BP+"pyodide.asm.js",Path.Combine(_root,"pyodide","pyodide.asm.js"),lg);
    DownloadFile(BP+"pyodide-lock.json",Path.Combine(_root,"pyodide","pyodide-lock.json"),lg);
    DownloadFile(BP+"pyodide.asm.wasm",Path.Combine(_root,"pyodide","pyodide.asm.wasm"),lg); }
  lg.Line("setup terminado");
}
    static void RunFix(JobLog lg){ lg.Line("[fix] re-descarga wllama.wasm (single y multi)");
      // tambien el index.js de la carpeta plana: si es 2.x hay que reponerlo o la GPU
      // sigue anulada aunque los .wasm se descarguen bien.
      try{ File.Delete(Path.Combine(_root,"wllama","index.js"));}catch{}
      try{ File.Delete(Path.Combine(_root,"wllama","wasm","wllama.wasm"));}catch{}
      try{ File.Delete(Path.Combine(_root,"wllama","wllama.wasm"));}catch{}
      try{ File.Delete(Path.Combine(_root,"wllama","multi-thread","wllama.wasm"));}catch{}
      try{ File.Delete(Path.Combine(_root,"wllama","single-thread","wllama.wasm"));}catch{}
      try{ File.Delete(Path.Combine(_root,"wllama",WLLAMA_VER,"index.js"));}catch{}
      foreach(string r in new string[]{"multi-thread","single-thread","wasm"}){
        try{ File.Delete(Path.Combine(_root,"wllama",WLLAMA_VER,r,"wllama.wasm"));}catch{} }
      lg.Line("[fix] recuerda limpiar la cache del service worker (DevTools > Application > Clear site data), si no el navegador sigue sirviendo el 2.x cacheado");
      RunSetup("wllama",lg); }
    static void AddEntry(ZipArchive zip,string path,string entry){ ZipArchiveEntry en=zip.CreateEntry(entry); using(var es=en.Open()){ using(var fis=File.OpenRead(path)){ fis.CopyTo(es); } } }
    static string MakeZip(JobLog lg){
      try{ string[] files=new string[]{"index.html","sw.js","copito.bat","copito.sh","README.md","LICENSE",".gitignore"};
        string[] dirs=new string[]{"wllama","v86","pyodide"};
        string dst=Path.Combine(_root,"copito-portable.zip"); try{ File.Delete(dst);}catch{}
        using(var fs=new FileStream(dst,FileMode.Create)){ using(var zip=new ZipArchive(fs,ZipArchiveMode.Create)){
          foreach(string f in files){ string p=Path.Combine(_root,f); if(File.Exists(p)){ AddEntry(zip,p,f); lg.Line("  + "+f); } }
          foreach(string d in dirs){ string dp=Path.Combine(_root,d); if(Directory.Exists(dp)){ foreach(string fp in Directory.GetFiles(dp,"*",SearchOption.AllDirectories)){ string rel=d+"/"+fp.Substring(dp.Length+1).Replace('\\','/'); AddEntry(zip,fp,rel); } lg.Line("  + "+d+"/"); } }
        } }
        lg.Line("OK "+dst+" ("+(new FileInfo(dst).Length/1048576)+"MB)  [modelos/ NO incluido]");
        return "pack: "+dst; }
      catch(Exception e){ return "pack error: "+e.Message; }
    }
    static string DoFirewall(JobLog lg){
      string a1="advfirewall firewall add rule name=\""+RULE_W+"\" dir=in action=allow protocol=TCP localport=8080";
      string a2="advfirewall firewall add rule name=\""+RULE_A+"\" dir=in action=allow protocol=TCP localport=20666";
      string show=RunCapture("netsh","advfirewall firewall show rule name=\""+RULE_A+"\"");
      if(show.IndexOf(RULE_A)>=0 && show.IndexOf("Action:")>=0){ lg.Line("reglas ya presentes"); return "firewall: ya estaba abierto"; }
      lg.Line("creando reglas (Windows pedira permiso UAC)...");
      lg.Line(RunElevated("netsh",a1)); lg.Line(RunElevated("netsh",a2));
      string show2=RunCapture("netsh","advfirewall firewall show rule name=\""+RULE_A+"\"");
      bool ok2=show2.IndexOf(RULE_A)>=0;
      return ok2?"firewall: OK (puertos 8080 y 20666 abiertos en LAN)":"firewall: no confirmado (acepta el UAC y vuelve a pulsar)";
    }
    static string SetAutostart(bool on,JobLog lg){
      try{ using(var k=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run",true)){
        if(on){ k.SetValue("Copito","cmd /c start \"Copito\" /min \"\" \""+_self+"\""); lg.Line("autostart ON"); }
        else { k.DeleteValue("Copito",false); lg.Line("autostart OFF"); } }
        return "autostart: "+(on?"activado (Copito arrancara solo al encender)":"desactivado"); }
      catch(Exception e){ return "autostart error: "+e.Message; }
    }
    static bool AutostartOn(){ try{ using(var k=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run",false)){ return k!=null && k.GetValue("Copito")!=null; } }catch{ return false; } }
    static Dictionary<string,object> AdminStatus(){
      string vidx=Path.Combine(_root,"wllama",WLLAMA_VER,"index.js");
      string pidx=Path.Combine(_root,"wllama","index.js");
      // gpu = 1 solo si el runtime que se va a usar tiene WebGPU (si no, n_gpu_layers se ignora)
      string useIdx=HasWebGPU(vidx)?vidx:pidx;
      bool cw=File.Exists(useIdx) && (ValidWasm(Path.Combine(Path.GetDirectoryName(useIdx),"multi-thread","wllama.wasm"))||ValidWasm(Path.Combine(Path.GetDirectoryName(useIdx),"wasm","wllama.wasm"))||ValidWasm(Path.Combine(Path.GetDirectoryName(useIdx),"wllama.wasm")));
      bool cg=HasWebGPU(useIdx);
      bool cv=File.Exists(Path.Combine(_root,"v86","libv86.js"));
      bool cp=File.Exists(Path.Combine(_root,"pyodide","pyodide.js"));
      string sh=RunCapture("netsh","advfirewall firewall show rule name=\""+RULE_A+"\"");
      bool fw=sh.IndexOf(RULE_A)>=0 && sh.IndexOf("Action:")>=0;
      return new Dictionary<string,object>{
        {"os","windows"},{"web_port",8080},{"api_port",20666},{"root",_root},{"wllama_ver",WLLAMA_VER},
        {"components",new Dictionary<string,object>{{"wllama",cw?1:0},{"wllama_gpu",cg?1:0},{"v86",cv?1:0},{"pyodide",cp?1:0}}},
        {"firewall",new Dictionary<string,object>{{"endpoint",fw?1:0}}},
        {"autostart",AutostartOn()?1:0},{"endpoint_enabled",_enabled?1:0},{"model",_model}
      };
    }
    static string StartJob(Action<JobLog> work){ string id=Guid.NewGuid().ToString(); JobLog jl=new JobLog(); _ajobs[id]=jl;
      ThreadPool.QueueUserWorkItem(delegate{ try{ work(jl); }catch(Exception e){ jl.Line("[error] "+e.Message); } jl.Done=true; }); return id; }

    static readonly Dictionary<string,string> MIME=new Dictionary<string,string>{
      {".html","text/html; charset=utf-8"},{".htm","text/html; charset=utf-8"},{".js","text/javascript; charset=utf-8"},{".mjs","text/javascript; charset=utf-8"},
      {".css","text/css; charset=utf-8"},{".json","application/json; charset=utf-8"},{".wasm","application/wasm"},{".bin","application/octet-stream"},{".iso","application/octet-stream"},
      {".gguf","application/octet-stream"},{".png","image/png"},{".jpg","image/jpeg"},{".jpeg","image/jpeg"},{".svg","image/svg+xml"},{".ico","image/x-icon"},{".woff2","font/woff2"},{".txt","text/plain; charset=utf-8"},{".md","text/markdown; charset=utf-8"} };
    static void HandleWeb(TcpClient c){
      NetworkStream s=c.GetStream(); c.NoDelay=true; Req r=ReadReq(s); string m=r.Method,p=r.Path;
      if(m=="OPTIONS"){ SendEmpty(s,204,"No Content"); return; }
      if(p.StartsWith("/__copito/admin/")){ if(!IsInternal(c)){ SendJson(s,403,"Forbidden",new Dictionary<string,object>{{"error","internal only"}}); return; } AdminApi(s,r,m,p); return; }
      if(p=="/health"){ SendJson(s,200,"OK",new Dictionary<string,object>{{"ok",1},{"web",1},{"api_enabled",_enabled?1:0},{"model",_model}}); return; }
      string rel=r.Path.TrimStart('/'); if(rel.Length==0) rel="index.html"; string full;
      try{ full=Path.GetFullPath(Path.Combine(_root,rel)); }catch{ SendJson(s,400,"Bad Request",new Dictionary<string,object>{{"error","bad path"}}); return; }
      string rf=_root.EndsWith(Path.DirectorySeparatorChar.ToString())?_root:_root+Path.DirectorySeparatorChar;
      if(!(full==_root||full.StartsWith(rf))){ SendJson(s,403,"Forbidden",new Dictionary<string,object>{{"error","forbidden"}}); return; }
      if(!File.Exists(full)){ SendJson(s,404,"Not Found",new Dictionary<string,object>{{"error","not found"}}); return; }
      FileInfo fi=new FileInfo(full); long total=fi.Length; string ext=Path.GetExtension(full).ToLower(); string mime; if(!MIME.TryGetValue(ext,out mime)) mime="application/octet-stream";
      bool noStore=(ext==".html"||ext==".htm"||ext==".js"||ext==".mjs"); long start=0,end=total-1; bool partial=false;
      if(r.Headers.ContainsKey("range")&&m=="GET"){ string rg=r.Headers["range"]; int eq=rg.IndexOf('='); if(eq>=0&&rg.Substring(0,eq).Trim().ToLower()=="bytes"){ string spec=rg.Substring(eq+1); int dash=spec.IndexOf('-'); if(dash>=0){ string a=spec.Substring(0,dash).Trim(), b=spec.Substring(dash+1).Trim(); if(a.Length>0) long.TryParse(a,out start); if(b.Length>0) long.TryParse(b,out end); if(start>end||start>=total){ SendHead(s,416,"Range Not Satisfiable",new Dictionary<string,string>{{"Content-Range","bytes */"+total}},true); s.Flush(); return; } if(end>=total) end=total-1; partial=true; } } }
      long len=end-start+1; Dictionary<string,string> ex=new Dictionary<string,string>(); ex["Content-Type"]=mime; ex["Accept-Ranges"]="bytes"; ex["Content-Length"]=len.ToString(); ex["Cache-Control"]=noStore?"no-store":"public, max-age=3600"; if(partial) ex["Content-Range"]="bytes "+start+"-"+end+"/"+total;
      SendHead(s,partial?206:200,partial?"Partial Content":"OK",ex,true);
      if(m!="HEAD"){ using(FileStream ffs=fi.OpenRead()){ ffs.Seek(start,SeekOrigin.Begin); byte[] buf=new byte[81920]; long left=len; while(left>0){ int n=ffs.Read(buf,0,(int)Math.Min(buf.Length,left)); if(n<=0) break; s.Write(buf,0,n); left-=n; } } } s.Flush();
    }
    static void AdminApi(NetworkStream s,Req r,string m,string p){
      if(p=="/__copito/admin/status"&&m=="GET"){ SendJson(s,200,"OK",AdminStatus()); return; }
      if(p=="/__copito/admin/job"&&m=="GET"){ string qid=QueryVal(r,"id"); JobLog jl; if(qid!=null&&_ajobs.TryGetValue(qid,out jl)){ Dictionary<string,object> o=new Dictionary<string,object>(); o["done"]=jl.Done?1:0; o["log"]=jl.Snap(); o["result"]=jl.Result; SendJson(s,200,"OK",o); if(jl.Done){ JobLog tmp; _ajobs.TryRemove(qid,out tmp); } } else SendJson(s,404,"Not Found",new Dictionary<string,object>{{"error","job gone"}}); return; }
      Dictionary<string,object> d=(m=="POST")?(JS.DeserializeObject(r.Body) as Dictionary<string,object>):null;
      if(p=="/__copito/admin/firewall"&&m=="POST"){ string id2=StartJob(delegate(JobLog lg){ lg.Result=DoFirewall(lg); }); SendJson(s,200,"OK",new Dictionary<string,object>{{"jobId",id2}}); return; }
      if(p=="/__copito/admin/setup"&&m=="POST"){ string which=(d!=null)?GStr(d,"which"):null; if(which==null) which="all"; string id3=StartJob(delegate(JobLog lg){ RunSetup(which,lg); lg.Result="setup: "+which+" terminado"; }); SendJson(s,200,"OK",new Dictionary<string,object>{{"jobId",id3}}); return; }
      if(p=="/__copito/admin/fix"&&m=="POST"){ string id4=StartJob(delegate(JobLog lg){ RunFix(lg); lg.Result="fix terminado"; }); SendJson(s,200,"OK",new Dictionary<string,object>{{"jobId",id4}}); return; }
      if(p=="/__copito/admin/pack"&&m=="POST"){ string id5=StartJob(delegate(JobLog lg){ lg.Result=MakeZip(lg); }); SendJson(s,200,"OK",new Dictionary<string,object>{{"jobId",id5}}); return; }
      if(p=="/__copito/admin/autostart"&&m=="POST"){ bool on=(d!=null)&&GBool(d,"on"); string id6=StartJob(delegate(JobLog lg){ lg.Result=SetAutostart(on,lg); }); SendJson(s,200,"OK",new Dictionary<string,object>{{"jobId",id6}}); return; }
      SendJson(s,404,"Not Found",new Dictionary<string,object>{{"error","not found"}});
    }

    static void HandleApi(TcpClient c){
      NetworkStream s=c.GetStream(); c.NoDelay=true; Req r=ReadReq(s); string m=r.Method,p=r.Path;
      if(m=="OPTIONS"){ SendEmpty(s,204,"No Content"); return; }
      if(p=="/health"){ SendJson(s,200,"OK",new Dictionary<string,object>{{"ok",1},{"enabled",_enabled?1:0},{"model",_model},{"api_key_set",string.IsNullOrEmpty(_apiKey)?0:1},{"pending_jobs",_jobs.Count}}); return; }
      if(p=="/v1/models"&&m=="GET"){ if(!AuthOk(r)){ SendJson(s,401,"Unauthorized",ErrObj("invalid api key")); return; } if(!_enabled){ SendJson(s,503,"Service Unavailable",ErrObj("endpoint disabled")); return; } SendJson(s,200,"OK",new Dictionary<string,object>{{"object","list"},{"data",new object[]{new Dictionary<string,object>{{"id",_model},{"object","model"},{"owned_by","copito"}}}}}); return; }
      if(p=="/v1/messages/count_tokens"&&m=="POST"){ CountTokens(s,r); return; }
      if(p=="/v1/messages"&&m=="POST"){ Messages(s,r); return; }
      if(p=="/v1/chat/completions"&&m=="POST"){ Chat(s,r); return; }
      if(p.StartsWith("/__copito/")){ Internal(c,s,r,m,p); return; }
      SendJson(s,404,"Not Found",ErrObj("not found"));
    }
    static List<object> AsList(object o){ List<object> res=new List<object>(); if(o==null) return res; string s0=o as string; if(s0!=null) return res; System.Collections.IEnumerable en=o as System.Collections.IEnumerable; if(en==null) return res; foreach(object x in en) res.Add(x); return res; }
    static string GetText(object content){
      if(content==null) return "";
      string s=content as string; if(s!=null) return s;
      List<object> arr=AsList(content); StringBuilder sb=new StringBuilder();
      foreach(object item in arr){ Dictionary<string,object> dic=item as Dictionary<string,object>; if(dic==null) continue; string type=GStr(dic,"type");
        if(type=="text"){ string t=GStr(dic,"text"); if(!string.IsNullOrEmpty(t)){ if(sb.Length>0) sb.Append("\n"); sb.Append(t); } }
        else if(type=="image"){ if(sb.Length>0) sb.Append("\n"); sb.Append("[imagen omitida]"); }
        else { object tv=GObj(dic,"text"); string ts=tv as string; if(!string.IsNullOrEmpty(ts)){ if(sb.Length>0) sb.Append("\n"); sb.Append(ts); } } }
      return sb.ToString();
    }
    static Dictionary<string,object> Msg(string role,string content){ Dictionary<string,object> m=new Dictionary<string,object>(); m["role"]=role; m["content"]=content; return m; }
    static List<object> AnthToOpenAI(Dictionary<string,object> d){
      List<object> outp=new List<object>();
      string sys=GetText(GObj(d,"system")); if(!string.IsNullOrEmpty(sys)) outp.Add(Msg("system",sys));
      List<object> messages=AsList(GObj(d,"messages"));
      foreach(object mo in messages){ Dictionary<string,object> md=mo as Dictionary<string,object>; if(md==null) continue; string role=GStr(md,"role"); if(string.IsNullOrEmpty(role)) role="user"; if(role!="assistant") role="user"; outp.Add(Msg(role,GetText(GObj(md,"content")))); }
      return outp;
    }
    static Dictionary<string,object> AnthErr(string typ,string msg){ return new Dictionary<string,object>{{"type","error"},{"error",new Dictionary<string,object>{{"type",typ},{"message",msg}}}}; }
    static int EstimateTokens(List<object> msgs){ int n=0; foreach(object mo in msgs){ Dictionary<string,object> md=mo as Dictionary<string,object>; if(md==null) continue; string c=md["content"] as string; if(c!=null) n+=Math.Max(1,c.Length/4); } if(n==0) n=1; return n; }
    static void WriteAnthEvent(NetworkStream s,string ev,object o){ byte[] bb=Encoding.UTF8.GetBytes("event: "+ev+"\ndata: "+JS.Serialize(o)+"\n\n"); s.Write(bb,0,bb.Length); s.Flush(); }
    static void CountTokens(NetworkStream s,Req r){
      if(!AuthOk(r)){ SendJson(s,401,"Unauthorized",AnthErr("authentication_error","invalid api key")); return; }
      Dictionary<string,object> d=JS.DeserializeObject(r.Body) as Dictionary<string,object>; if(d==null){ SendJson(s,400,"Bad Request",AnthErr("invalid_request_error","invalid json")); return; }
      SendJson(s,200,"OK",new Dictionary<string,object>{{"input_tokens",EstimateTokens(AnthToOpenAI(d))}});
    }
    static void Messages(NetworkStream s,Req r){
      if(!AuthOk(r)){ SendJson(s,401,"Unauthorized",AnthErr("authentication_error","invalid api key")); return; }
      if(!_enabled){ SendJson(s,503,"Service Unavailable",AnthErr("overloaded_error","Copito endpoint disabled.")); return; }
      Dictionary<string,object> d=JS.DeserializeObject(r.Body) as Dictionary<string,object>; if(d==null){ SendJson(s,400,"Bad Request",AnthErr("invalid_request_error","invalid json")); return; }
      string requested=GStr(d,"model"); if(string.IsNullOrEmpty(requested)) requested=_model;
      bool stream=GBool(d,"stream"); List<object> msgs=AnthToOpenAI(d);
      if(msgs.Count==0){ SendJson(s,400,"Bad Request",AnthErr("invalid_request_error","messages required")); return; }
      object maxTok=GObj(d,"max_tokens"); if(maxTok==null) maxTok=4096;
      string id="msg_"+Guid.NewGuid().ToString("N").Substring(0,24); int inputTokens=EstimateTokens(msgs);
      Dictionary<string,object> payload=new Dictionary<string,object>(); payload["id"]=id; payload["model"]=requested; payload["messages"]=msgs; payload["stream"]=stream; payload["max_tokens"]=maxTok; payload["temperature"]=GObj(d,"temperature");
      Job job=new Job(); job.Id=id; job.Payload=payload; _jobs[id]=job; _pollQ.Enqueue(id); _pollEvt.Set();
      if(stream){ Dictionary<string,string> ex=new Dictionary<string,string>(); ex["Content-Type"]="text/event-stream"; ex["Cache-Control"]="no-cache"; SendHead(s,200,"OK",ex,false);
        try{
          WriteAnthEvent(s,"message_start",new Dictionary<string,object>{{"type","message_start"},{"message",new Dictionary<string,object>{{"id",id},{"type","message"},{"role","assistant"},{"model",requested},{"content",new object[]{}},{"stop_reason",null},{"stop_sequence",null},{"usage",new Dictionary<string,object>{{"input_tokens",inputTokens},{"output_tokens",0}}}}}});
          WriteAnthEvent(s,"content_block_start",new Dictionary<string,object>{{"type","content_block_start"},{"index",0},{"content_block",new Dictionary<string,object>{{"type","text"},{"text",""}}}});
          string full="";
          while(true){ Item it; if(!NextItem(job,out it)){ WriteAnthEvent(s,"error",AnthErr("timeout_error","timeout")); break; }
            if(it.Type=="chunk"){ string txt=it.Text==null?"":it.Text; full+=txt; WriteAnthEvent(s,"content_block_delta",new Dictionary<string,object>{{"type","content_block_delta"},{"index",0},{"delta",new Dictionary<string,object>{{"type","text_delta"},{"text",txt}}}}); }
            else if(it.Type=="done"){ int outTokens=Math.Max(1,full.Length/4); WriteAnthEvent(s,"content_block_stop",new Dictionary<string,object>{{"type","content_block_stop"},{"index",0}}); WriteAnthEvent(s,"message_delta",new Dictionary<string,object>{{"type","message_delta"},{"delta",new Dictionary<string,object>{{"stop_reason","end_turn"},{"stop_sequence",null}}},{"usage",new Dictionary<string,object>{{"output_tokens",outTokens}}}}); WriteAnthEvent(s,"message_stop",new Dictionary<string,object>{{"type","message_stop"}}); break; }
            else if(it.Type=="error"){ WriteAnthEvent(s,"error",AnthErr("api_error",it.Error==null?"error":it.Error)); break; } }
        }catch{} finally{ Job tmp; _jobs.TryRemove(id,out tmp); } return; }
      string full2="";
      try{ while(true){ Item it; if(!NextItem(job,out it)) throw new Exception("timeout"); if(it.Type=="chunk") full2+=(it.Text==null?"":it.Text); else if(it.Type=="done") break; else if(it.Type=="error") throw new Exception(it.Error==null?"error":it.Error); } }
      catch(Exception e){ Job tmp; _jobs.TryRemove(id,out tmp); SendJson(s,500,"Internal Server Error",AnthErr("api_error",e.Message)); return; }
      Job tmp2; _jobs.TryRemove(id,out tmp2);
      int outTokens2=Math.Max(1,full2.Length/4);
      SendJson(s,200,"OK",new Dictionary<string,object>{{"id",id},{"type","message"},{"role","assistant"},{"model",requested},{"content",new object[]{new Dictionary<string,object>{{"type","text"},{"text",full2}}}},{"stop_reason","end_turn"},{"stop_sequence",null},{"usage",new Dictionary<string,object>{{"input_tokens",inputTokens},{"output_tokens",outTokens2}}}});
    }
    static void Chat(NetworkStream s,Req r){
      if(!AuthOk(r)){ SendJson(s,401,"Unauthorized",ErrObj("invalid api key")); return; }
      if(!_enabled){ SendJson(s,503,"Service Unavailable",ErrObj("Copito endpoint disabled.")); return; }
      Dictionary<string,object> d=JS.DeserializeObject(r.Body) as Dictionary<string,object>; if(d==null){ SendJson(s,400,"Bad Request",ErrObj("invalid json")); return; }
      object msgs=GObj(d,"messages"); if(msgs==null){ SendJson(s,400,"Bad Request",ErrObj("messages required")); return; }
      string model=GStr(d,"model"); if(model==null) model=_model; bool stream=GBool(d,"stream"); string id=Guid.NewGuid().ToString();
      Dictionary<string,object> payload=new Dictionary<string,object>(); payload["id"]=id; payload["model"]=model; payload["messages"]=msgs; payload["stream"]=stream; payload["max_tokens"]=GObj(d,"max_tokens"); payload["temperature"]=GObj(d,"temperature");
      Job job=new Job(); job.Id=id; job.Payload=payload; _jobs[id]=job; _pollQ.Enqueue(id); _pollEvt.Set();
      if(stream){ Dictionary<string,string> ex=new Dictionary<string,string>(); ex["Content-Type"]="text/event-stream"; ex["Cache-Control"]="no-cache"; SendHead(s,200,"OK",ex,false);
        try{ while(true){ Item it; if(!NextItem(job,out it)) break;
            if(it.Type=="chunk"){ Dictionary<string,object> delta=new Dictionary<string,object>{{"content",it.Text}}; Dictionary<string,object> ck=new Dictionary<string,object>{{"index",0},{"delta",delta},{"finish_reason",null}}; WriteSse(s,new Dictionary<string,object>{{"id",id},{"object","chat.completion.chunk"},{"model",model},{"choices",new object[]{ck}}}); }
            else if(it.Type=="done"){ string fm=it.Model!=null?it.Model:model; Dictionary<string,object> dk=new Dictionary<string,object>{{"index",0},{"delta",new Dictionary<string,object>()},{"finish_reason","stop"}}; WriteSse(s,new Dictionary<string,object>{{"id",id},{"object","chat.completion.chunk"},{"model",fm},{"choices",new object[]{dk}}}); byte[] dn=Encoding.UTF8.GetBytes("data: [DONE]\n\n"); s.Write(dn,0,dn.Length); s.Flush(); break; }
            else if(it.Type=="error"){ WriteSse(s,ErrObj(it.Error)); break; } } }
        catch{} finally{ Job tmp; _jobs.TryRemove(id,out tmp); } return; }
      string full=""; object usage=null; string finalModel=model;
      try{ while(true){ Item it; if(!NextItem(job,out it)) throw new Exception("timeout"); if(it.Type=="chunk") full+=it.Text; else if(it.Type=="done"){ usage=it.Usage; if(it.Model!=null) finalModel=it.Model; break; } else if(it.Type=="error") throw new Exception(it.Error); } }
      catch(Exception e){ Job tmp; _jobs.TryRemove(id,out tmp); SendJson(s,500,"Internal Server Error",ErrObj(e.Message)); return; }
      Job tmp2; _jobs.TryRemove(id,out tmp2);
      if(usage==null){ int ct=Math.Max(1,full.Length/4); usage=new Dictionary<string,object>{{"prompt_tokens",0},{"completion_tokens",ct},{"total_tokens",ct}}; }
      Dictionary<string,object> msg=new Dictionary<string,object>{{"role","assistant"},{"content",full}}; Dictionary<string,object> chOut=new Dictionary<string,object>{{"index",0},{"message",msg},{"finish_reason","stop"}};
      SendJson(s,200,"OK",new Dictionary<string,object>{{"id",id},{"object","chat.completion"},{"model",finalModel},{"choices",new object[]{chOut}},{"usage",usage}});
    }
    static bool NextItem(Job job,out Item it){ if(job.Out.TryDequeue(out it)) return true; bool got=job.Evt.Wait(JOB_WAIT); job.Evt.Reset(); if(job.Out.TryDequeue(out it)) return true; it=null; return false; }
    static void Internal(TcpClient c,NetworkStream s,Req r,string m,string p){
      if(!IsInternal(c)){ SendJson(s,403,"Forbidden",new Dictionary<string,object>{{"error","internal only"}}); return; }
      if(p=="/__copito/poll"&&m=="GET"){ string jid; if(!_pollQ.TryDequeue(out jid)){ bool sig=_pollEvt.Wait(POLL_WAIT); _pollEvt.Reset(); if(!_pollQ.TryDequeue(out jid)){ SendEmpty(s,204,"No Content"); return; } } Job job; if(_jobs.TryGetValue(jid,out job)) SendJson(s,200,"OK",job.Payload); else SendJson(s,404,"Not Found",new Dictionary<string,object>{{"error","job gone"}}); return; }
      Dictionary<string,object> d=(m=="POST")?(JS.DeserializeObject(r.Body) as Dictionary<string,object>):null;
      if(p=="/__copito/config"&&m=="POST"&&d!=null){ object en; if(d.TryGetValue("enabled",out en)){ bool? bb=en as bool?; if(bb.HasValue) _enabled=bb.Value; } string ak=GStr(d,"api_key"); if(ak!=null) _apiKey=ak; string md=GStr(d,"model"); if(md!=null&&md.Length>0) _model=md; SendJson(s,200,"OK",new Dictionary<string,object>{{"ok",1},{"state",new Dictionary<string,object>{{"enabled",_enabled?1:0},{"model",_model},{"api_key_set",string.IsNullOrEmpty(_apiKey)?0:1}}}}); return; }
      if(m=="POST"&&d!=null){ string jid=GStr(d,"job_id"); Job job; if(jid==null||!_jobs.TryGetValue(jid,out job)){ SendJson(s,404,"Not Found",new Dictionary<string,object>{{"error","job gone"}}); return; } Item it=new Item(); if(p=="/__copito/chunk"){ it.Type="chunk"; it.Text=GStr(d,"text"); } else if(p=="/__copito/done"){ it.Type="done"; it.Model=GStr(d,"model"); it.Usage=GObj(d,"usage"); } else if(p=="/__copito/error"){ it.Type="error"; it.Error=GStr(d,"error"); } else { SendJson(s,404,"Not Found",new Dictionary<string,object>{{"error","not found"}}); return; } job.Out.Enqueue(it); job.Evt.Set(); SendJson(s,200,"OK",new Dictionary<string,object>{{"ok",1}}); return; }
      SendJson(s,404,"Not Found",new Dictionary<string,object>{{"error","not found"}});
    }
  }
}
'@

function Start-Copito{
  Add-Type -ReferencedAssemblies 'System','System.Core','System.Web.Extensions','System.IO.Compression' -TypeDefinition $CsharpCode
  $lan=@(); try{ $u=New-Object System.Net.Sockets.UdpClient; $u.Connect('8.8.8.8',80); $lan+=$u.Client.LocalEndPoint.Address.ToString(); $u.Close() }catch{}
  Write-Host ''
  Write-Host '[ok] Copito activo - web :8080 + endpoint :20666 (COOP+COEP => wllama multithread)' -ForegroundColor Green
  Write-Host ("   Web:      http://localhost:{0}/" -f $WEB_PORT) -ForegroundColor Cyan
  Write-Host ("   Endpoint: http://127.0.0.1:{0}/v1  (OpenAI) y /v1/messages (Anthropic)" -f $API_PORT) -ForegroundColor Cyan
  foreach($ip in $lan){ Write-Host ("   LAN:      http://{0}:{1}/" -f $ip,$WEB_PORT) -ForegroundColor DarkCyan }
  Write-Host ''
  Write-Host '[info] Firewall, instalar, reparar, empaquetar, inicio auto: boton [Server] en la web.' -ForegroundColor Yellow
  Write-Host ''
  try{ [Copito.Server]::Start($WEB_PORT,$API_PORT,$ROOT,$env:COPIITO_SELF) }catch{ $script:FAILED=$true; Write-Host ("[error] " + $_.Exception.Message) -ForegroundColor Red; exit 1 }
  try{ Start-Process ("http://localhost:{0}/" -f $WEB_PORT) }catch{}
  Write-Host '[web] abriendo Copito...' -ForegroundColor Magenta
  while($true){ Start-Sleep -Seconds 3600 }
}

try{ Start-Copito }catch{ $script:FAILED=$true; Write-Host ("[error] " + $_.Exception.Message) -ForegroundColor Red; Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed }
if($script:FAILED){ Read-Host "`n[enter] para cerrar" }