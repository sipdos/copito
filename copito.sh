#!/usr/bin/env bash
# ============================================================================
# Copito - archivo unico (macOS/Linux). Sin Python. Perl core preinstalado.
#   :8080  -> web + API admin (/__copito/admin/*, solo localhost)
#   :20666 -> endpoint OpenAI (/v1/*) + Anthropic (/v1/messages)
# Headers COOP/COEP habilitan SharedArrayBuffer => wllama multi-thread
# ============================================================================
set -u
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(dirname "$SELF")"
WEB_PORT=8080; API_PORT=20666
have(){ command -v "$1" >/dev/null 2>&1; }
have perl || { echo "perl no encontrado (viene preinstalado en macOS/Linux)."; exit 1; }
echo ""
echo "[ok] Copito activo - web :$WEB_PORT + endpoint :$API_PORT (COOP+COEP => wllama multithread)"
echo "   Web:      http://localhost:$WEB_PORT/"
echo "   Endpoint: http://127.0.0.1:$API_PORT/v1  (OpenAI) y /v1/messages (Anthropic)"
echo "   Firewall/instalar/reparar/empaquetar/inicio-auto: boton [Server] en la web."
echo "   (cierra esta ventana para parar todo)"
echo ""
_os="$(uname -s)"
if [ "$_os" = Darwin ]; then have open && open "http://localhost:$WEB_PORT/" >/dev/null 2>&1 || true
else have xdg-open && xdg-open "http://localhost:$WEB_PORT/" >/dev/null 2>&1 || true; fi
exec perl -x "$SELF" "$WEB_PORT" "$API_PORT" "$ROOT" "$SELF"
#!perl
use strict; use warnings;
use IO::Socket::INET; use IO::Select; use JSON::PP; use Errno qw(EAGAIN EWOULDBLOCK EINTR);
$|=1; $SIG{PIPE}='IGNORE';
my ($WEB_PORT,$API_PORT,$ROOT,$SELF)=@ARGV; $ROOT//='.'; $ROOT=~s{/+$}{}; $SELF//=$0;
my $PORT_WEB=$WEB_PORT||8080; my $PORT_API=$API_PORT||20666;
my $J=JSON::PP->new->utf8->canonical->allow_nonref;
my %CFG=(enabled=>0,api_key=>'',model=>'copito-local');
my %C; my @POLLQ; my @PEND; my %JOBS;
my $sr=IO::Select->new; my $sw=IO::Select->new;
my $POLLW=25; my $JOBW=300;
# Version de wllama que usa/setup. Global para que la vean admin_status y run_setup.
# Debe coincidir con WLLAMA_VER en copito.bat y con WLLAMA_VER en index.html.
my $VER='3.6.1'; my $B361='https://cdn.jsdelivr.net/npm/@wllama/wllama@3.6.1/esm/';
sub jenc{$J->encode($_[0])} sub jdec{my $r=eval{$J->decode($_[0])};$r}
sub cors{"Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: credentialless\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET,POST,OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type,Authorization,x-api-key,anthropic-version\r\nAccess-Control-Max-Age: 86400\r\n"}
sub head{my($code,$st,$ex,$close)=@_; my $h="HTTP/1.1 $code $st\r\n".cors(); $h.="Connection: close\r\n" if $close; if(ref $ex eq 'HASH'){for(keys %$ex){$h.="$_: $ex->{$_}\r\n"}} $h.="\r\n"; $h}
sub out{my($fn,$b)=@_; my $c=$C{$fn} or return; $c->{out}.=$b; $sw->add($c->{sock})}
sub jsonr{my($code,$st,$o)=@_; my $b=jenc($o); head($code,$st,{'Content-Type'=>'application/json','Content-Length'=>length $b},1).$b}
sub emptys{my($code,$st)=@_; head($code,$st,{'Content-Length'=>'0'},1)}
sub sse{my($o)=@_; "data: ".jenc($o)."\n\n"}
sub killc{my($fn)=@_; my $c=delete $C{$fn} or return; eval{$sr->remove($c->{sock})}; eval{$sw->remove($c->{sock})}; eval{close $c->{sock}}; @POLLQ=grep{$_!=$fn}@POLLQ; for my $id(keys %JOBS){my $j=$JOBS{$id}; $j->{waiters}=[grep{$_!=$fn}@{$j->{waiters}}]; delete $JOBS{$id} unless @{$j->{waiters}};}}
sub internal{my($s)=@_; my $ip=eval{$s->peerhost}//''; return $ip eq '127.0.0.1'||$ip eq '::1'||$ip eq 'localhost'}
sub authok{my($h)=@_; my $k=$CFG{api_key}; return 1 unless defined $k && length $k; my $x=$h->{'x-api-key'}//''; my $a=$h->{authorization}//''; return $x eq $k || $a eq "Bearer $k" || lc($a) eq "bearer ".lc($k)}
sub parse{my($buf)=@_; my $i=index($buf,"\r\n\r\n"); return undef if $i<0; my $hd=substr($buf,0,$i); my @ln=split/\r\n/,$hd; my @f=split/ /,$ln[0]; my %h; for my $k(1..$#ln){my $c=index($ln[$k],':'); next if $c<1; my $kk=lc substr($ln[$k],0,$c); my $vv=substr($ln[$k],$c+1); $vv=~s/^\s+|\s+$//g; $h{$kk}=$vv} my $cl=$h{'content-length'}//0; my $need=$i+4+$cl; return undef if length($buf)<$need; my $body=substr($buf,$i+4,$cl); my $rest=substr($buf,$need); return {method=>$f[0],rawpath=>($f[1]//'/'),path=>(split/\?/,($f[1]//'/'),2)[0],headers=>\%h,body=>$body,rest=>$rest}}
sub qval{my($r,$key)=@_; my $q=$r->{rawpath}; my $i=index($q,'?'); return undef if $i<0; for my $kv(split/&/,substr($q,$i+1)){ my $e=index($kv,'='); next if $e<1; return substr($kv,$e+1) if substr($kv,0,$e) eq $key; } return undef }
sub deliver{while(@POLLQ && @PEND){my $pfn=shift @POLLQ; my $id=shift @PEND; my $job=$JOBS{$id} or next; my $c=$C{$pfn} or next; out($pfn,jsonr(200,'OK',$job->{payload})); $c->{close}=1}}
sub addconn{my($sock,$kind)=@_; $sock->blocking(0); my $fn=fileno($sock); $C{$fn}={sock=>$sock,kind=>$kind,in=>'',out=>'',state=>'http',close=>0,deadline=>undef,job=>undef,fh=>undef,rem=>0}; $sr->add($sock)}

# ---------- admin (unix: sincrono) ----------
sub have_cmd{my($c)=@_; return scalar(which($c))>0}
sub which{my($c)=@_; for my $d(split/:/,$ENV{PATH}//''){ return "$d/$c" if -x "$d/$c" } return () }
sub valid_wasm{my($p)=@_; return 0 unless -f $p; my $sz=-s $p; return 0 if $sz<1000000; open(my $f,'<:raw',$p) or return 0; my $b; read($f,$b,4); close $f; return (unpack('C4',$b) eq join('',map{chr}0,0x61,0x73,0x6d))?1:0}
sub dl{my($url,$dest,$log)=@_; my $dir=$dest; $dir=~s{/[^/]+$}{}; my @segs=split m{/},$dir; my $acc=''; for my $sg(@segs){ $acc.=$sg eq ''?'/':"$sg/"; mkdir $acc unless -d $acc }
  my $ok=0; for my $t (1..3){ my $rc = have_cmd('curl') ? system('curl','-fsSL','--max-time','300','-o',$dest,$url) : (have_cmd('wget') ? system('wget','-q','-T','300','-O',$dest,$url) : 1);
    if($rc==0 && -s $dest){ $ok=1; push @$log,"  OK $dest"; last } push @$log,"  ! intento $t rc=$rc"; unlink $dest if -e $dest; }
  push @$log,"  X fallo $url" unless $ok; return $ok }
sub has_webgpu{my($p)=@_; return 0 unless -f $p; open(my $f,'<',$p) or return 0; local $/; my $t=<$f>; close $f; return ($t=~/requestAdapter|navigator\.gpu|GPUBufferUsage/)?1:0}
sub run_setup{my($which,$log)=@_; my $all=(!$which||$which eq 'all');
  my $BV='https://copy.sh/v86/'; my $BP='https://cdn.jsdelivr.net/pyodide/v0.26.4/full/';
  if($all||$which eq 'wllama'){ push @$log,"[wllama v$VER: usa tu carpeta ./wllama/; esto solo repara si falta]";
    my $idx="$ROOT/wllama/index.js";
    # Si el index.js existe pero es 2.x (sin WebGPU) se reemplaza: antes el "unless -f"
    # lo daba por bueno para siempre y dejaba n_gpu_layers anulado (GPU muerta, tok/s bajos).
    if(-f $idx && !has_webgpu($idx)){ push @$log,"  ! wllama 2.x sin WebGPU en ./wllama/index.js -> se reemplaza por v$VER";
      unlink $idx; unlink "$ROOT/wllama/wasm/wllama.wasm"; unlink "$ROOT/wllama/wllama.wasm"; unlink "$ROOT/wllama/multi-thread/wllama.wasm"; unlink "$ROOT/wllama/single-thread/wllama.wasm"; }
    dl($B361.'index.js',$idx,$log) unless -f $idx;
    my $w1="$ROOT/wllama/wasm/wllama.wasm"; dl($B361.'wasm/wllama.wasm',$w1,$log) unless valid_wasm($w1);
    my $mt="$ROOT/wllama/multi-thread/wllama.wasm";
    if(!valid_wasm($mt)){ if(valid_wasm($w1)){ my $d=$mt; $d=~s{/[^/]+$}{}; mkdir $d unless -d $d; copy($w1,$mt); push @$log,"  copiado multi-thread desde wasm/" } else { dl($B361.'multi-thread/wllama.wasm',$mt,$log) } }
    my $st="$ROOT/wllama/single-thread/wllama.wasm";
    if(!valid_wasm($st)){ if(valid_wasm($w1)){ my $d=$st; $d=~s{/[^/]+$}{}; mkdir $d unless -d $d; copy($w1,$st); push @$log,"  copiado single-thread desde wasm/" } else { dl($B361.'wllama.wasm',$st,$log) } }
    # Carpeta VERSIONADA ./wllama/<ver>/ : es la que index.html prefiere (WLLAMA_BASES[0]).
    my $vd="$ROOT/wllama/$VER"; my $vidx="$vd/index.js";
    dl($B361.'index.js',$vidx,$log) if !-f $vidx || !has_webgpu($vidx);
    for my $r (qw(multi-thread/wllama.wasm single-thread/wllama.wasm wasm/wllama.wasm)){ my $vp="$vd/$r"; dl($B361.$r,$vp,$log) unless valid_wasm($vp) }
    push @$log,"  versionado en ./wllama/$VER/" }
  if($all||$which eq 'v86'){ push @$log,"[v86] (~100MB)"; dl($BV.'build/libv86.js',"$ROOT/v86/libv86.js",$log); dl($BV.'build/v86.wasm',"$ROOT/v86/v86.wasm",$log); dl($BV.'bios/seabios.bin',"$ROOT/v86/bios/seabios.bin",$log); dl($BV.'bios/vgabios.bin',"$ROOT/v86/bios/vgabios.bin",$log); dl($BV.'images/buildroot.iso',"$ROOT/v86/images/buildroot.iso",$log); }
  if($all||$which eq 'pyodide'){ push @$log,"[pyodide]"; dl($BP.'pyodide.js',"$ROOT/pyodide/pyodide.js",$log); dl($BP.'pyodide.asm.js',"$ROOT/pyodide/pyodide.asm.js",$log); dl($BP.'pyodide-lock.json',"$ROOT/pyodide/pyodide-lock.json",$log); dl($BP.'pyodide.asm.wasm',"$ROOT/pyodide/pyodide.asm.wasm",$log); }
  push @$log,"setup terminado" }
sub run_fix{my($log)=@_; push @$log,"[fix] re-descarga wllama.wasm (single y multi)";
  unlink "$ROOT/wllama/index.js"; unlink "$ROOT/wllama/wasm/wllama.wasm"; unlink "$ROOT/wllama/wllama.wasm"; unlink "$ROOT/wllama/multi-thread/wllama.wasm"; unlink "$ROOT/wllama/single-thread/wllama.wasm";
  unlink "$ROOT/wllama/3.6.1/index.js"; unlink "$ROOT/wllama/3.6.1/multi-thread/wllama.wasm"; unlink "$ROOT/wllama/3.6.1/single-thread/wllama.wasm"; unlink "$ROOT/wllama/3.6.1/wasm/wllama.wasm";
  push @$log,"[fix] recuerda limpiar la cache del service worker (DevTools > Application > Clear site data)";
  run_setup('wllama',$log) }
sub run_pack{my($log)=@_; my @items; for my $f (qw(index.html sw.js copito.bat copito.sh README.md LICENSE .gitignore)){ push @items,$f if -e "$ROOT/$f" } for my $d (qw(wllama v86 pyodide)){ push @items,$d if -d "$ROOT/$d" }
  unless(@items){ push @$log,"X nada"; return "pack: vacio" } my $dst="$ROOT/copito-portable";
  if(have_cmd('zip')){ my $rc=system('zip','-rq',$dst.'.zip',@items); push @$log,($rc==0?"OK $dst.zip":"X zip"); return "pack: $dst.zip" }
  elsif(have_cmd('tar')){ my $rc=system('tar','czf',$dst.'.tar.gz',@items); push @$log,($rc==0?"OK $dst.tar.gz":"X tar"); return "pack: $dst.tar.gz" }
  push @$log,"X ni zip ni tar"; return "pack: sin herramienta" }
sub run_firewall{my($log)=@_; push @$log,"en macOS/Linux el firewall de apps normalmente no bloquea LAN inbound."; push @$log,"si usas ufw (Linux): sudo ufw allow 8080/tcp && sudo ufw allow 20666/tcp"; push @$log,"en macOS: Preferencias > Red > Firewall, o socketfilterfw (requiere root)."; return "firewall: nota (unix no suele necesitarlo)" }
sub autostart_path{ my $os=`uname -s`; chomp $os; if($os eq 'Darwin'){ return "$ENV{HOME}/Library/LaunchAgents/local.copito.plist" } return "$ENV{HOME}/.config/autostart/copito.desktop" }
sub autostart_on{ return -f autostart_path()?1:0 }
sub set_autostart{my($on,$log)=@_; my $os=`uname -s`; chomp $os; my $p=autostart_path();
  if($on){ my $dir=$p; $dir=~s{/[^/]+$}{}; my @segs=split m{/},$dir; my $acc=''; for my $sg(@segs){ $acc.=$sg eq ''?'/':"$sg/"; mkdir $acc unless -d $acc }
    open(my $f,'>',$p) or do{ push @$log,"X no se pudo escribir $p"; return "autostart error" };
    if($os eq 'Darwin'){ print $f qq{<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Label</key><string>local.copito</string><key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>run</string></array><key>RunAtLoad</key><true/><key>KeepAlive</key><false/></dict></plist>\n}; close $f; system('launchctl','load',$p); }
    else { print $f "[Desktop Entry]\nType=Application\nName=Copito\nExec=/bin/bash $SELF run\nTerminal=true\nX-GNOME-Autostart-enabled=true\n"; close $f; }
    push @$log,"autostart ON ($p)"; return "autostart: activado" }
  else { unlink $p; if($os eq 'Darwin'){ system('launchctl','unload',$p) } push @$log,"autostart OFF"; return "autostart: desactivado" } }
sub admin_status{ my $os=`uname -s`; chomp $os;
  # Igual que copito.bat: gpu=1 solo si el runtime que se usara tiene WebGPU.
  # Con un wllama 2.x n_gpu_layers se ignora y la GPU no se usara nunca.
  my $vidx="$ROOT/wllama/$VER/index.js"; my $pidx="$ROOT/wllama/index.js";
  my $dir=(-f $vidx && has_webgpu($vidx)) ? "$ROOT/wllama/$VER" : "$ROOT/wllama";
  my $use="$dir/index.js";
  my $cg=has_webgpu($use)?1:0;
  my $cw=(-f $use && (valid_wasm("$dir/multi-thread/wllama.wasm")||valid_wasm("$dir/single-thread/wllama.wasm")||valid_wasm("$dir/wasm/wllama.wasm")||valid_wasm("$dir/wllama.wasm")))?1:0;
  my $cv=(-f "$ROOT/v86/libv86.js")?1:0; my $cp=(-f "$ROOT/pyodide/pyodide.js")?1:0;
  return {os=>$os,web_port=>$PORT_WEB,api_port=>$PORT_API,root=>$ROOT,wllama_ver=>$VER,components=>{wllama=>$cw,wllama_gpu=>$cg,v86=>$cv,pyodide=>$cp},firewall=>{endpoint=>-1},autostart=>autostart_on(),endpoint_enabled=>$CFG{enabled}?1:0,model=>$CFG{model}} }
sub admin_api{my($fn,$c,$r,$m,$p)=@_; internal($c->{sock}) or do{out($fn,jsonr(403,'Forbidden',{error=>'internal only'})); $c->{close}=1; return};
  if($p eq '/__copito/admin/status' && $m eq 'GET'){ out($fn,jsonr(200,'OK',admin_status())); $c->{close}=1; return }
  my $bj=($m eq 'POST' && length($r->{body}//''))?jdec($r->{body}):undef;
  my @log; my $res='';
  if($p eq '/__copito/admin/firewall' && $m eq 'POST'){ $res=run_firewall(\@log) }
  elsif($p eq '/__copito/admin/setup' && $m eq 'POST'){ my $w=($bj&&$bj->{which})||'all'; run_setup($w,\@log); $res="setup: $w terminado" }
  elsif($p eq '/__copito/admin/fix' && $m eq 'POST'){ run_fix(\@log); $res='fix terminado' }
  elsif($p eq '/__copito/admin/pack' && $m eq 'POST'){ $res=run_pack(\@log) }
  elsif($p eq '/__copito/admin/autostart' && $m eq 'POST'){ $res=set_autostart(($bj&&$bj->{on})?1:0,\@log) }
  else { out($fn,jsonr(404,'Not Found',{error=>'not found'})); $c->{close}=1; return }
  out($fn,jsonr(200,'OK',{done=>1,log=>join("\n",@log),result=>$res})); $c->{close}=1; return }

# ---------- web ----------
sub mime{my($p)=@_; $p=lc $p; return 'text/html; charset=utf-8' if $p=~/\.html?$/; return 'application/javascript; charset=utf-8' if $p=~/\.(m?js)$/; return 'text/css; charset=utf-8' if $p=~/\.css$/; return 'application/json; charset=utf-8' if $p=~/\.json$/; return 'application/wasm' if $p=~/\.wasm$/; return 'image/png' if $p=~/\.png$/; return 'image/jpeg' if $p=~/\.jpe?g$/; return 'image/svg+xml' if $p=~/\.svg$/; return 'image/x-icon' if $p=~/\.ico$/; return 'text/plain; charset=utf-8' if $p=~/\.txt$/; return 'text/markdown; charset=utf-8' if $p=~/\.md$/; return 'application/octet-stream'}
sub serve{my($fn,$r)=@_; my $c=$C{$fn}; my $p=$r->{path}; $p='index.html' if $p eq '' || $p eq '/'; $p=~s{^/}{}; my $full="$ROOT/$p"; my $rp=eval{use Cwd 'abs_path'; abs_path($full)}//''; my $rr=eval{use Cwd 'abs_path'; abs_path($ROOT)}//''; unless($rp && $rr && index($rp,$rr)==0){out($fn,head(403,'Forbidden',{},1)); $c->{close}=1; return} unless(-f $full){out($fn,head(404,'Not Found',{},1)); $c->{close}=1; return} my $sz=-s $full; my $ct=mime($full); out($fn,head(200,'OK',{'Content-Type'=>$ct,'Content-Length'=>$sz,'Accept-Ranges'=>'bytes','Cache-Control'=>'no-cache'},0)); open(my $fh,'<:raw',$full) or do{out($fn,head(500,'Server Error',{},1)); $c->{close}=1; return}; $c->{state}='file'; $c->{fh}=$fh; $c->{rem}=$sz}
sub handle_web{my($fn,$r)=@_; my $c=$C{$fn}; my $m=uc($r->{method}); my $p=$r->{path};
  if($m eq 'OPTIONS'){out($fn,emptys(204,'No Content')); $c->{close}=1; return}
  if($p=~m{^/__copito/admin/}){ admin_api($fn,$c,$r,$m,$p); return }
  if($p eq '/health'){out($fn,jsonr(200,'OK',{ok=>1,web=>1,api_enabled=>$CFG{enabled}?1:0,model=>$CFG{model}})); $c->{close}=1; return}
  serve($fn,$r)}

# ---------- api ----------
sub next_item{my($job,$to)=@_; my $t0=time; while(time-$t0<$to){ if(@{$job->{outq}}){ return shift @{$job->{outq}} } select(undef,undef,undef,0.25); } return undef }
sub write_anth_event{my($fn,$evt,$o)=@_; out($fn,"event: $evt\ndata: ".jenc($o)."\n\n")}
sub anth_err{my($t,$m)=@_; {type=>'error',error=>{type=>$t,message=>$m}}}
sub est_tokens{my($m)=@_; return int(length($m)/4)+1}
sub anth_to_openai{my($d)=@_; my @o; if(defined $d->{system}){push @o,{role=>'system',content=>$d->{system}}} my $m=$d->{messages}//[]; for(@$m){push @o,{role=>($_->{role}//'user'),content=>($_->{content}//'')}} @o}
sub chat{my($fn,$r)=@_; my $c=$C{$fn}; authok($r->{headers}) or do{out($fn,jsonr(401,'Unauthorized',{error=>{message=>'invalid api key'}})); $c->{close}=1; return}; $CFG{enabled} or do{out($fn,jsonr(503,'Service Unavailable',{error=>{message=>'Copito endpoint disabled'}})); $c->{close}=1; return}; my $d=jdec($r->{body}//''); my $msgs=$d->{messages}; (ref $msgs eq 'ARRAY' && @$msgs) or do{out($fn,jsonr(400,'Bad Request',{error=>{message=>'messages required'}})); $c->{close}=1; return};
  my $model=$d->{model}//$CFG{model}; my $stream=$d->{stream}?1:0; my $id=sprintf("%08x-%04x-%04x-%04x-%012x",map{int(rand(0x10000))}1..4,time);
  my $job={id=>$id,payload=>{id=>$id,model=>$model,messages=>$msgs,stream=>$stream?1:0,max_tokens=>$d->{max_tokens},temperature=>$d->{temperature}},outq=>[],waiters=>[$fn]};
  $JOBS{$id}=$job; push @POLLQ,$id; deliver();
  if($stream){ out($fn,head(200,'OK',{'Content-Type'=>'text/event-stream','Cache-Control'=>'no-cache'},0));
    while(1){ my $it=next_item($job,600); last unless defined $it;
      if($it->{type} eq 'chunk'){ out($fn,sse({id=>$id,object=>'chat.completion.chunk',model=>$model,choices=>[{index=>0,delta=>{content=>($it->{text}//'')},finish_reason=>undef}]})) }
      elsif($it->{type} eq 'done'){ my $fm=$it->{model}//$model; out($fn,sse({id=>$id,object=>'chat.completion.chunk',model=>$fm,choices=>[{index=>0,delta=>{},finish_reason=>'stop'}]})); out($fn,"data: [DONE]\n\n"); last }
      elsif($it->{type} eq 'error'){ out($fn,sse({error=>{message=>($it->{error}//'error')}})); last } }
    delete $JOBS{$id}; $c->{close}=1; return }
  my $full=''; my $usage; my $fm=$model;
  while(1){ my $it=next_item($job,600); unless(defined $it){ delete $JOBS{$id}; out($fn,jsonr(500,'Internal Server Error',{error=>{message=>'timeout'}})); $c->{close}=1; return }
    if($it->{type} eq 'chunk'){ $full.=($it->{text}//'') } elsif($it->{type} eq 'done'){ $usage=$it->{usage}; $fm=$it->{model}//$model; last } elsif($it->{type} eq 'error'){ delete $JOBS{$id}; out($fn,jsonr(500,'Internal Server Error',{error=>{message=>($it->{error}//'error')}})); $c->{close}=1; return } }
  delete $JOBS{$id};
  $usage={prompt_tokens=>0,completion_tokens=>(length($full)?int(length($full)/4)+1:1),total_tokens=>(length($full)?int(length($full)/4)+1:1)} unless $usage;
  out($fn,jsonr(200,'OK',{id=>$id,object=>'chat.completion',model=>$fm,choices=>[{index=>0,message=>{role=>'assistant',content=>$full},finish_reason=>'stop'}],usage=>$usage})); $c->{close}=1 }
sub messages{my($fn,$r)=@_; my $c=$C{$fn}; authok($r->{headers}) or do{out($fn,jsonr(401,'Unauthorized',anth_err('authentication_error','invalid api key'))); $c->{close}=1; return}; $CFG{enabled} or do{out($fn,jsonr(503,'Service Unavailable',anth_err('overloaded_error','disabled'))); $c->{close}=1; return}; my $d=jdec($r->{body}//''); my $msgs=anth_to_openai($d//{}); @$msgs or do{out($fn,jsonr(400,'Bad Request',anth_err('invalid_request_error','messages required'))); $c->{close}=1; return};
  my $requested=$d->{model}//$CFG{model}; my $stream=$d->{stream}?1:0; my $id='msg_'.substr(sprintf("%08x%08x",time,int(rand(0xffffffff))),0,24); my $in_tok=est_tokens(jenc($d));
  my $job={id=>$id,payload=>{id=>$id,model=>$requested,messages=>$msgs,stream=>$stream?1:0,max_tokens=>($d->{max_tokens}//4096),temperature=>$d->{temperature}},outq=>[],waiters=>[$fn]};
  $JOBS{$id}=$job; push @POLLQ,$id; deliver();
  if($stream){ out($fn,head(200,'OK',{'Content-Type'=>'text/event-stream','Cache-Control'=>'no-cache'},0));
    write_anth_event($fn,'message_start',{type=>'message_start',message=>{id=>$id,type=>'message',role=>'assistant',model=>$requested,content=>[],stop_reason=>undef,usage=>{input_tokens=>$in_tok,output_tokens=>0}}});
    write_anth_event($fn,'content_block_start',{type=>'content_block_start',index=>0,content_block=>{type=>'text',text=>''}});
    my $full='';
    while(1){ my $it=next_item($job,600); unless(defined $it){ write_anth_event($fn,'error',anth_err('timeout_error','timeout')); last }
      if($it->{type} eq 'chunk'){ $full.=($it->{text}//''); write_anth_event($fn,'content_block_delta',{type=>'content_block_delta',index=>0,delta=>{type=>'text_delta',text=>($it->{text}//'')}}) }
      elsif($it->{type} eq 'done'){ my $ot=length($full)?int(length($full)/4)+1:1; write_anth_event($fn,'content_block_stop',{type=>'content_block_stop',index=>0}); write_anth_event($fn,'message_delta',{type=>'message_delta',delta=>{stop_reason=>'end_turn'},usage=>{output_tokens=>$ot}}); write_anth_event($fn,'message_stop',{type=>'message_stop'}); last }
      elsif($it->{type} eq 'error'){ write_anth_event($fn,'error',anth_err('api_error',$it->{error}//'error')); last } }
    delete $JOBS{$id}; $c->{close}=1; return }
  my $full='';
  while(1){ my $it=next_item($job,600); unless(defined $it){ delete $JOBS{$id}; out($fn,jsonr(500,'Internal Server Error',anth_err('api_error','timeout'))); $c->{close}=1; return }
    if($it->{type} eq 'chunk'){ $full.=($it->{text}//'') } elsif($it->{type} eq 'done'){ last } elsif($it->{type} eq 'error'){ delete $JOBS{$id}; out($fn,jsonr(500,'Internal Server Error',anth_err('api_error',$it->{error}//'error'))); $c->{close}=1; return } }
  delete $JOBS{$id};
  my $ot=length($full)?int(length($full)/4)+1:1;
  out($fn,jsonr(200,'OK',{id=>$id,type=>'message',role=>'assistant',model=>$requested,content=>[{type=>'text',text=>$full}],stop_reason=>'end_turn',usage=>{input_tokens=>$in_tok,output_tokens=>$ot}})); $c->{close}=1 }
sub handle_api{my($fn,$r)=@_; my $c=$C{$fn}; my $m=uc($r->{method}); my $p=$r->{path};
  if($m eq 'OPTIONS'){out($fn,emptys(204,'No Content')); $c->{close}=1; return}
  if($p eq '/health'){out($fn,jsonr(200,'OK',{ok=>1,enabled=>$CFG{enabled}?1:0,model=>$CFG{model},api_key_set=>(length($CFG{api_key})?1:0),pending_jobs=>scalar(keys %JOBS)})); $c->{close}=1; return}
  if($p eq '/v1/models' && $m eq 'GET'){ authok($r->{headers}) or do{out($fn,jsonr(401,'Unauthorized',{error=>{message=>'invalid api key'}})); $c->{close}=1; return}; $CFG{enabled} or do{out($fn,jsonr(503,'Service Unavailable',{error=>{message=>'endpoint disabled'}})); $c->{close}=1; return}; out($fn,jsonr(200,'OK',{object=>'list',data=>[{id=>$CFG{model},object=>'model',owned_by=>'copito'}]})); $c->{close}=1; return}
  if($p eq '/v1/messages/count_tokens' && $m eq 'POST'){ my $d=jdec($r->{body}//''); my $t=est_tokens(jenc($d)); out($fn,jsonr(200,'OK',{input_tokens=>$t})); $c->{close}=1; return}
  if($p eq '/v1/messages' && $m eq 'POST'){ messages($fn,$r); return }
  if($p eq '/v1/chat/completions' && $m eq 'POST'){ chat($fn,$r); return }
  if($p=~m{^/__copito/}){ internal_bridge($fn,$r,$m,$p); return }
  out($fn,jsonr(404,'Not Found',{error=>'not found'})); $c->{close}=1 }
sub internal_bridge{my($fn,$r,$m,$p)=@_; my $c=$C{$fn}; internal($c->{sock}) or do{out($fn,jsonr(403,'Forbidden',{error=>'internal only'})); $c->{close}=1; return};
  if($p eq '/__copito/poll' && $m eq 'GET'){ if(@PEND){ my $jid=shift @PEND; my $job=$JOBS{$jid}; if($job){out($fn,jsonr(200,'OK',$job->{payload})); $c->{close}=1; return} } $c->{state}='poll'; $c->{deadline}=time+$POLLW; push @POLLQ,$fn; return}
  if($p eq '/__copito/config' && $m eq 'POST'){ my $bj=jdec($r->{body}//''); $CFG{enabled}=$bj->{enabled}?1:0 if exists $bj->{enabled}; $CFG{api_key}=$bj->{api_key} if defined $bj->{api_key}; $CFG{model}=$bj->{model} if defined $bj->{model} && length $bj->{model}; out($fn,jsonr(200,'OK',{ok=>1,state=>{enabled=>$CFG{enabled}?1:0,model=>$CFG{model},api_key_set=>(length($CFG{api_key})?1:0)}})); $c->{close}=1; return}
  if($m eq 'POST'){ my $bj=jdec($r->{body}//''); my $jid=$bj->{job_id}//''; my $job=$JOBS{$jid}; unless($job){out($fn,jsonr(404,'Not Found',{error=>'job gone'})); $c->{close}=1; return}
    if($p eq '/__copito/chunk'){ push @{$job->{outq}},{type=>'chunk',text=>($bj->{text}//'')} }
    elsif($p eq '/__copito/done'){ push @{$job->{outq}},{type=>'done',model=>$bj->{model},usage=>$bj->{usage}} }
    elsif($p eq '/__copito/error'){ push @{$job->{outq}},{type=>'error',error=>($bj->{error}//'error')} }
    else {out($fn,jsonr(404,'Not Found',{error=>'not found'})); $c->{close}=1; return}
    out($fn,jsonr(200,'OK',{ok=>1})); $c->{close}=1; return}
  out($fn,jsonr(404,'Not Found',{error=>'not found'})); $c->{close}=1 }

sub handle{my($fn,$r)=@_; my $c=$C{$fn} or return; if($c->{kind} eq 'web'){ handle_web($fn,$r) } else { handle_api($fn,$r) } }
sub onread{my($fn)=@_; my $c=$C{$fn} or return; my $chunk; my $n=sysread($c->{sock},$chunk,65536); if(!defined $n){my $e=0+$!; return if $e==0+EAGAIN||$e==0+EWOULDBLOCK||$e==0+EINTR; killc($fn); return} $n==0 and do{killc($fn); return}; $c->{in}.=$chunk; while(1){ my $r=parse($c->{in}); last unless $r; $c->{in}=$r->{rest}; handle($fn,$r); last if $c->{close} } }
sub onwrite{my($fn)=@_; my $c=$C{$fn} or return; return unless length $c->{out}; my $n=syswrite($c->{sock},$c->{out}); if(!defined $n){my $e=0+$!; return if $e==0+EAGAIN||$e==0+EWOULDBLOCK||$e==0+EINTR; killc($fn); return} $c->{out}=substr($c->{out},$n); if(!length $c->{out}){ $sw->remove($c->{sock}); killc($fn) if $c->{close} } }
sub pump{ for my $fn(keys %C){ my $c=$C{$fn}; next unless $c->{state} eq 'file' && $c->{fh}; next if length($c->{out})>262144; my $rd=$c->{rem}<65536?$c->{rem}:65536; my $buf; my $n=sysread($c->{fh},$buf,$rd); if(!defined $n || $n==0){ close $c->{fh}; $c->{fh}=undef; $c->{close}=1; next } $c->{rem}-=$n; $c->{out}.=$buf; $sw->add($c->{sock}); if($c->{rem}<=0){ close $c->{fh}; $c->{fh}=undef; $c->{close}=1 } } }
sub expire{ my $now=time; for my $fn(keys %C){ my $c=$C{$fn}; next unless defined $c->{deadline}; next if $now<$c->{deadline}; if($c->{state} eq 'poll'){ out($fn,emptys(204,'No Content')); $c->{close}=1; @POLLQ=grep{$_!=$fn}@POLLQ } $c->{deadline}=undef } }

my $lw=IO::Socket::INET->new(LocalAddr=>'0.0.0.0',LocalPort=>$PORT_WEB,Proto=>'tcp',Listen=>128,ReuseAddr=>1,Blocking=>0) or die "web $PORT_WEB: $!\n";
my $la=IO::Socket::INET->new(LocalAddr=>'0.0.0.0',LocalPort=>$PORT_API,Proto=>'tcp',Listen=>128,ReuseAddr=>1,Blocking=>0) or do{ close $lw; die "api $PORT_API: $!\n" };
$sr->add($lw); $sr->add($la);
print "[ok] Copito (Perl) - web :$PORT_WEB  api :$PORT_API  (COOP+COEP)\n";
while(1){ my $t=1.0; my $now=time; for my $c(values %C){ next unless defined $c->{deadline}; my $d=$c->{deadline}-$now; $t=$d if $d<$t } $t=0 if $t<0; my @r=$sr->can_read($t); for my $h(@r){ if($h==$lw){ my $cli=$lw->accept; addconn($cli,'web') if defined $cli } elsif($h==$la){ my $cli=$la->accept; addconn($cli,'api') if defined $cli } else { my $fn=fileno($h); onread($fn) if $C{$fn} } } my @w=$sw->can_write(0); for my $h(@w){ my $fn=fileno($h); onwrite($fn) if $C{$fn} } pump(); expire() }