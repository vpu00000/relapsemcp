local a={cache={}::any}do do local function __modImpl()
local function sanitize(b,c,d,e)
e.remaining-=1
if e.remaining<0 then return"<output limit>"end
local f=typeof(b)
if f=="Instance"then
local g,h=pcall(function()return b:GetFullName()end)
return if g then string.sub(h,1,500)else"<Instance>"
end
if f=="string"then return if#b>500 then b:sub(1,500).."… [truncated]"else b end
if f=="number"or f=="boolean"or f=="nil"then return b end
if f~="table"then return"<"..f..">"end
if c>=8 then return"<max depth>"end
if d[b]then return"<repeated table>"end
d[b]=true
local g={}
local h=0
for i,j in next,b do
h+=1
if h>60 or e.remaining<=0 then
g.__omitted="more entries omitted"
break
end
local k=type(i)
local l=if k=="string"then i:sub(1,500)
elseif k=="number"then i else"<"..k.." key "..h..">"
g[l]=sanitize(j,c+1,d,e)
end
return g
end

local function serialize(b)
local c=type(b)
if c=="string"then return string.format("%q",b)end
if c=="number"or c=="boolean"then return tostring(b)end
if c=="nil"then return"nil"end
local d={}
for e,f in next,b do
d[#d+1]="["..serialize(e).."] = "..serialize(f)
end
return"{"..table.concat(d,", ").."}"
end

return{
Format=function(b)
local c=sanitize(b,0,{},{remaining=2048})
return serialize(if type(c)=="table"then c else{c})
end,
Error=function(b)
local c=type(b)
return if c=="string"then b:sub(1,1000)
elseif c=="number"or c=="boolean"then tostring(b)
else"<"..c.." error>"
end,
}end function a.a():typeof(__modImpl())local b=a.cache.a if not b then b={c=__modImpl()}a.cache.a=b end return b.c end end do local function __modImpl()



local b=10000
local c=131072
local d=524288
local e=16777216
local f=0.25
local g=131072
local h=16

return function(i)
local j={}
local k=setmetatable({},{__mode="v"})
local l={}
local m,n,o={},1,0
local p,q,r,s=0,0,0,0
local t=false
local u,v,w,x=false,false,false,false
local y=0
local z,A
local B=0
local C=i.HttpService:GenerateGUID(false)
local D=os.time()*1000
local E=true
local F,G=decompile,getscriptbytecode

local function finished()
return w and n>o and not x
end

local function emit(H,I,J,K)
B+=1
return i.Send({type="script-sources",scripts=H,removedScriptIds=I,
sourcesToMap=p+(if t then 1 else 0),
processedSources=q+(if t then 1 else 0),
skippedSources=r+(if t then 1 else 0),
hasFinishedMapping=finished(),mappingSessionId=C,
mappingSessionStartedAt=D,mappingRevision=B,
beginMappingSession=K==true},J)
end

local function scriptId(H)
local I,J=pcall(function()return H:GetDebugId()end)
return if I and type(J)=="string"and#J<=256 then J else nil
end

local function pathOf(H)
local I,J=pcall(function()return H:GetFullName()end)
return if I and type(J)=="string"then J:sub(1,2048)else"<script>"
end

local function add(H)
if not u then return end
local I,J=pcall(i.IsScript,H)
if not I or not J then return end
local K=scriptId(H)
if not K then return end
local L=j[K]
if L then
L.removed=false
L.path=pathOf(H)
k[K]=H
l[K]=L
return
end
if p>=b or o-n+1>=b then
t=true
E=true
return
end


L={debugId=K,path=pathOf(H),status="queued",pendingInstance=H}
j[K]=L
k[K]=H
p+=1
o+=1
m[o]=L
E=true
end

local function remove(H)
local I,J=pcall(i.IsScript,H)
if not I or not J then return end
local K=scriptId(H)
local L=K and j[K]
if not L then return end

L.removed=true
l[K]=L
end

local function sourceEntry(H)
return{debugId=H.debugId,path=H.path,source=H.source}
end

local function flush()
local H,I,J,K={},{},0,0
for L,M in l do
l[L]=nil
if M.removed then
j[L]=nil
k[L]=nil
p-=1
if M.status~="queued"then q-=1 end
if M.status=="skipped"then r-=1 end
if M.source then s-=#M.source end
M.source=nil
M.pendingInstance=nil
I[#I+1]=L
elseif M.source then
H[#H+1]=sourceEntry(M)
J+=#M.source+#M.path+#L+256
end
K+=1
if K>=h or J>=g then break end
end
if E or K>0 then
E=false
emit(H,I)
end
end

local function readSource(H,I)
local J=scriptId(H)
local K=J and j[J]
if K and K.source and not K.removed then return K.source end
if x or os.clock()<y then
return nil,"Decompiler is busy or cooling down. Try again shortly."
end
if I and type(G)~="function"then
return nil,"getscriptbytecode is required to enforce the automatic indexing input limit."
end
x=true
local L=os.clock()
local M,N,O=pcall(function()
if I then
local M=G(H)
if type(M)~="string"or#M==0 then return nil,"Script bytecode is unavailable."end
if#M>c then return nil,"Script exceeds the 128 KiB automatic indexing bytecode limit."end
end
local M=F(H)
if type(M)~="string"or#M==0 then return nil,"Failed to decompile script."end
if I and#M>d then return nil,"Script exceeds the 512 KiB automatic indexing source limit."end
return M
end)


y=os.clock()+math.max(f,(os.clock()-L)*4)
x=false
if not M then return nil,i.Error(N)end
return N,O
end

local function discover()
local function collect(H)
for I,J in H do
H[I]=nil
if not u then return end
add(J)
if I%128==0 then task.wait()end
end
end
collect(game:QueryDescendants"LuaSourceContainer")
if u and type(getnilinstances)=="function"then
local H,I=pcall(getnilinstances)
if H and type(I)=="table"then collect(I)end
end
end

local function work()
while n<=o do
local H=m[n]
if H and not H.removed and j[H.debugId]==H then
if x or os.clock()<y then return end
local I=H.pendingInstance
local J
if I and s<e then J=readSource(I,true)end
if not u then return end
if j[H.debugId]==H and not H.removed then
if J and s+#J<=e then
H.source=J
s+=#J
H.status="mapped"
l[H.debugId]=H
else
H.status="skipped"
r+=1
end
q+=1
end
m[n]=nil
H.pendingInstance=nil
n+=1
E=true
break
end
m[n]=nil
n+=1
E=true
end
if n>o then
m,n,o={},1,0
elseif n>b then
local H={}
for I=n,o do H[#H+1]=m[I]end
m,n,o=H,1,#H
end
end

return{
Start=function()
if v then return end
v,u=true,true
z=game.DescendantAdded:Connect(add)
A=game.DescendantRemoving:Connect(remove)
task.spawn(function()
setthreadidentity(8)
task.wait(2)
if not u then return end
local H=pcall(discover)
if not u then return end
if not H then t=true end
w,E=true,true
while u do
flush()
work()
flush()
task.wait(f)
end
end)
end,
Sync=function(H)
emit({},{},H,true)
task.spawn(function()


local I={}
for J in j do I[#I+1]=J end
local J,K={},0
for L,M in I do
if not u or not H.Connected then return end
local N=j[M]
if N and N.source and not N.removed then
J[#J+1]=sourceEntry(N)
K+=#N.source+#N.path+#M+256
if#J>=h or K>=g then
if not emit(J,{},H)then return end
J,K={},0
task.wait(f)
end
end
end
if u and H.Connected then emit(J,{},H)end
end)
end,
GetScriptByDebugId=function(H)return k[H]end,


DecompileScriptSource=function(H)return readSource(H,false)end,
Stop=function()
u=false
if z then z:Disconnect()end
if A then A:Disconnect()end
table.clear(j)
table.clear(k)
table.clear(l)
table.clear(m)
end,
}
end end function a.b():typeof(__modImpl())local b=a.cache.b if not b then b={c=__modImpl()}a.cache.b=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.LogService

c:BindToType("execute",function(e)
task.defer(function()
setthreadidentity(8)
loadstring(e.source)()
end)
end)

c:BindToTypeRaw("get-console-output",function(e)
local f=math.max(1,math.min(tonumber(e.limit)or 20,200))
local g=e.logsOrder or"NewestFirst"
local h=e.filter
local i=typeof(h)=="string"and h~=""
local j=e.summaryOnly==true

local k=d:GetLogHistory()
local l={}
local m=0
local n={}

local function matchesFilter(o)
if not i then return true end
return string.find(o.message,h,1,true)~=nil
end

local o=500
local function formatLogMessage(p)
local q=tostring(p or"")
if#q>o then
q=string.sub(q,1,o)
.."…(+"..(#q-o).." chars omitted)"
end
return q
end

if g=="NewestFirst"then
for p=#k,1,-1 do
local q=k[p]
if not matchesFilter(q)then continue end

m+=1
local r=q.messageType and q.messageType.Name or"Unknown"
n[r]=(n[r]or 0)+1
if#l<f then
table.insert(l,q)
end
end
else
for p,q in k do
if not matchesFilter(q)then continue end

m+=1
local r=q.messageType and q.messageType.Name or"Unknown"
n[r]=(n[r]or 0)+1
if#l<f then
table.insert(l,q)
end
end
end

local p={}
if j then
table.insert(p,string.format("Matched %d logs.",m))
for q,r in n do
table.insert(p,string.format("%s: %d",q,r))
end
return table.concat(p,"\n")
end

table.insert(p,string.format("Displaying %d/%d logs:",#l,m))

for q,r in l do
table.insert(p,string.format(
"[%s t=%s] %s",
r.messageType.Name,tostring(r.timestamp),
formatLogMessage(r.message)
))
end

return table.concat(p,"\n")
end)

c:BindToType("get-data-by-code",function(e)
setthreadidentity(8)
local f=table.pack(loadstring(e.source)())

return f
end)
end end function a.c():typeof(__modImpl())local b=a.cache.c if not b then b={c=__modImpl()}a.cache.c=b end return b.c end end do local function __modImpl()

return function(b,c)
c:BindToTypeRaw("get-script-content",function(d)
local e
if d.debugId then
e=b.GetScriptByDebugId(d.debugId)
assert(e,"No live script instance found for DebugId: "..tostring(d.debugId))
else
setthreadidentity(8)
e=loadstring(d.source)()
assert(typeof(e)=="Instance","Script instance is not an instance.")
assert(e:IsA"LuaSourceContainer","Script instance is not a LuaSourceContainer.")
assert(not(e:IsA"Script"and e.RunContext~=Enum.RunContext.Client),
"Script instance is server-only.")
end
local f,g=b.DecompileScriptSource(e)
assert(f,g or"Failed to decompile script.")


local h,i=1,1
while true do
local j=string.find(f,"\n",i,true)
if not j then break end
h+=1
i=j+1
end
local j=math.max(1,math.min(tonumber(d.maxLines)or 80,2000))
local k=math.max(1,math.min(tonumber(d.startLine)or 1,h))
local l=math.max(k,math.min(tonumber(d.endLine)or h,h))
local m=math.min(l,k+j-1)
i=1
for n=1,k-1 do i=string.find(f,"\n",i,true)+1 end
local n,o=i,#f
for p=k,m do
local q=string.find(f,"\n",i,true)
if p==m then o=if q then q-1 else#f end
if q then i=q+1 end
end

local p=1048576
local q=o-n+1>p
local r=if m<l then
"\n-- Output truncated to "..j.." lines. Rerun with startLine="..(m+1).."."
else""
if q then r="\n-- Output truncated to 1 MiB. Request a smaller line range."end
return"-- Lines "..k.."-"..m.." of "..h.."\n"..
string.sub(f,n,math.min(o,n+p-1))..r
end)
end end function a.d():typeof(__modImpl())local b=a.cache.d if not b then b={c=__modImpl()}a.cache.d=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.MarketplaceService
local e=b.RobloxReplicatedStorage

c:BindToType("search-instances",function(f)
local g=loadstring("return "..f.root)()
local h=g:QueryDescendants(f.selector)

local i=math.max(1,math.min(tonumber(f.limit)or 20,100))
local j={}

for k,l in h do
if k>i then break end

local m=l.Name
pcall(function()m=l:GetFullName()end)

table.insert(j,{
Name=l.Name,
ClassName=l.ClassName,
Path=m,
DebugId=l:GetDebugId()
})
end

return{
count=#h,
limited=#h>i,
results=j
}
end)

c:BindToType("get-game-info",function(f)
local g=d:GetProductInfo(game.PlaceId)

local h={
PlaceId=game.PlaceId,
GameId=game.GameId,
PlaceVersion=game.PlaceVersion,
PlaceName=g.Name,
Creator=g.Creator.Name,
CreatorType=tostring(g.Creator.CreatorType),
CreatorId=g.Creator.CreatorTargetId,
JobId=game.JobId,
ServerType=e.GetServerType:InvokeServer()
}



if f.includeDescription==true then
h.PlaceDescription=g.Description
end

return h
end)

c:BindToType("get-descendants-tree",function(f)
local g=loadstring("return "..f.root)()
assert(typeof(g)=="Instance","Root path did not resolve to a valid Instance.")

local h=math.max(0,math.min(tonumber(f.maxDepth)or 2,5))
local i=math.max(1,math.min(tonumber(f.maxChildren)or 20,30))
local j=f.classFilter or""
local k=j~=""
local l=f.summaryOnly==true
local m=300
local n=m
local o=false

if l then
local p={}
local q=0
local r=0

local function walk(s,t)
if t>h then
return
end

for u,v in s:GetChildren()do
q+=1
if not k or v:IsA(j)then
r+=1
p[v.ClassName]=(p[v.ClassName]or 0)+1
end
if t<h then
walk(v,t+1)
end
end
end

walk(g,1)

return{
Root={
Name=g.Name,
ClassName=g.ClassName,
ChildCount=#g:GetChildren(),
},
MaxDepth=h,
ClassFilter=if k then j else nil,
VisitedDescendants=q,
MatchedDescendants=r,
ClassCounts=p,
}
end

local function buildTree(p,q)
if q>h then
return nil
end

local r=p:GetChildren()
local s={}
local t=0
local u=#r

for v,w in r do
if t>=i then break end
if n<=0 then
o=true
break
end

if k and not w:IsA(j)then


if q<h then
local x=buildTree(w,q+1)
if x and x.Children and#x.Children>0 then
table.insert(s,x)
t+=1
end
end
continue
end

n-=1

local x={
Name=w.Name,
ClassName=w.ClassName,
ChildCount=#w:GetChildren()
}

if q<h and x.ChildCount>0 then
local y=buildTree(w,q+1)
if y then
x.Children=y.Children
end
end

table.insert(s,x)
t+=1
end

return{
Name=p.Name,
ClassName=p.ClassName,
ChildCount=u,
TruncatedAt=if t<u then t else nil,
Children=s
}
end

local p=buildTree(g,0)
if o and typeof(p)=="table"then
p.Note="Output capped at "..m.." nodes. Narrow with classFilter, lower maxDepth, or summaryOnly=true."
end
return p
end)
end end function a.e():typeof(__modImpl())local b=a.cache.e if not b then b={c=__modImpl()}a.cache.e=b end return b.c end end do local function __modImpl()

return function(b,c)
c:BindToType("ensure-remote-spy",function(d)
if getgenv().Cobalt then
return{
status="already_loaded",
message="Cobalt remote spy is already running."
}
end


local e,f=pcall(function()
loadstring(game:HttpGet"https://gitlab.com/upio/cobalt/-/releases/permalink/latest/downloads/Cobalt.luau")()
end)

if not e then
error("Failed to load Cobalt: "..tostring(f))
end


local g=os.clock()
while not getgenv().Cobalt and os.clock()-g<10 do
task.wait(0.1)
end

assert(getgenv().Cobalt,"Cobalt loaded but failed to initialize within 10 seconds.")

return{
status="loaded",
message="Cobalt remote spy loaded successfully."
}
end)

c:BindToType("get-remote-spy-logs",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local f=d.direction or"Both"
local g=d.remoteNameFilter or""
local h=math.max(1,math.min(tonumber(d.limit)or 10,100))
local i=math.max(0,math.min(tonumber(d.maxCallsPerRemote)or 2,20))
local j=d.summaryOnly==true
local k=g~=""

local function ProcessLogs(l,m)
local n={}

for o,p in l do
local q=p.Instance
if typeof(q)~="Instance"then continue end
if#n>=h then break end

local r=""
local s=""
pcall(function()
r=q.Name
s=q.ClassName
end)


if k and not string.find(string.lower(r),string.lower(g),1,true)then
continue
end


local t={}
local u=#p.Calls
local v=math.max(1,u-i+1)

if not j then
for w=v,u do
local x=p.Calls[w]
if not x then continue end

table.insert(t,{
Index=w,
Arguments=x.Arguments,
Origin=x.Origin,
IsExecutor=x.IsExecutor or false,
IsActor=x.IsActor or false,
Line=x.Line,
})
end
end

table.insert(n,{
RemoteName=r,
RemoteClass=s,
Direction=m,
Method=p.Method
or(((e.shared.FunctionForClasses or{})[m])or{})[s],
TotalCalls=u,
Ignored=p.Ignored,
Blocked=p.Blocked,
RecentCalls=if j then nil else t,
})
end

return n
end

local l={}

if f=="Outgoing"or f=="Both"then
local m=ProcessLogs(e.shared.Logs.Outgoing,"Outgoing")
for n,o in m do
table.insert(l,o)
end
end

if f=="Incoming"or f=="Both"then
local m=ProcessLogs(e.shared.Logs.Incoming,"Incoming")
for n,o in m do
table.insert(l,o)
end
end


table.sort(l,function(m,n)
return m.TotalCalls>n.TotalCalls
end)


if#l>h then
local m={}
for n=1,h do
m[n]=l[n]
end
l=m
end

return{
count=#l,
results=l
}
end)
end end function a.f():typeof(__modImpl())local b=a.cache.f if not b then b={c=__modImpl()}a.cache.f=b end return b.c end end do local function __modImpl()

return function(b,c)
c:BindToType("clear-remote-spy-logs",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.ClearLogs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

e.shared.ClearLogs()

return{
status="cleared",
message="All remote spy logs have been cleared."
}
end)

c:BindToType("block-remote",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local f=d.remoteName
local g=d.direction
local h=d.shouldBlock

local i=e.shared.Logs[g]
assert(i,"Invalid direction: "..tostring(g))

for j,k in i do
local l=k.Instance
if typeof(l)~="Instance"then continue end

local m=""
pcall(function()m=l.Name end)

if m==f then
if h and not k.Blocked then
k:Block()
elseif not h and k.Blocked then
k:Block()
end

return{
status="success",
message=(h and"Blocked"or"Unblocked").." remote: "..f,
blocked=k.Blocked
}
end
end

error("Remote not found: "..f.." in "..g.." logs. Make sure the remote has been logged at least once.")
end)

c:BindToType("ignore-remote",function(d)
local e=getgenv().Cobalt
assert(e and e.shared and e.shared.Logs,"Cobalt remote spy is not loaded. Call ensure-remote-spy first.")

local f=d.remoteName
local g=d.direction
local h=d.shouldIgnore

local i=e.shared.Logs[g]
assert(i,"Invalid direction: "..tostring(g))

for j,k in i do
local l=k.Instance
if typeof(l)~="Instance"then continue end

local m=""
pcall(function()m=l.Name end)

if m==f then
if h and not k.Ignored then
k:Ignore()
elseif not h and k.Ignored then
k:Ignore()
end

return{
status="success",
message=(h and"Ignoring"or"Unignored").." remote: "..f,
ignored=k.Ignored
}
end
end

error("Remote not found: "..f.." in "..g.." logs. Make sure the remote has been logged at least once.")
end)




c:BindToType("remote-spy",function(d)
c.Callbacks["ensure-remote-spy"]{}

local e=d.operation
if e=="status"then
local f=getgenv().Cobalt
local function CountLogs(g)
local h=0
if typeof(g)~="table"then return h end
for i in g do
h+=1
end
return h
end

return{
status="loaded",
outgoingRemotes=CountLogs(f.shared and f.shared.Logs and f.shared.Logs.Outgoing),
incomingRemotes=CountLogs(f.shared and f.shared.Logs and f.shared.Logs.Incoming),
}
elseif e=="list"then
return c.Callbacks["get-remote-spy-logs"]{
direction=d.direction,
remoteNameFilter=d.nameFilter,
limit=d.limit,
maxCallsPerRemote=d.maxCallsPerRemote,
summaryOnly=d.summaryOnly,
}
elseif e=="clear"then
return c.Callbacks["clear-remote-spy-logs"]{}
elseif e=="block"or e=="unblock"then
return c.Callbacks["block-remote"]{
remoteName=d.remoteName,
direction=d.direction,
shouldBlock=e=="block",
}
elseif e=="ignore"or e=="unignore"then
return c.Callbacks["ignore-remote"]{
remoteName=d.remoteName,
direction=d.direction,
shouldIgnore=e=="ignore",
}
end

error("Invalid remote-spy operation: "..tostring(e))
end)
end end function a.g():typeof(__modImpl())local b=a.cache.g if not b then b={c=__modImpl()}a.cache.g=b end return b.c end end do local function __modImpl()

return function(b,c)
local d=b.VirtualInputManager

c:BindToType("type-text-box",function(e)
local f=e.path
local g=e.string or e.text
local h=e.enter
local i=e.useKeyPress

local j
if typeof(f)=="string"then
j=loadstring("return "..f)()
else
j=f
end

assert(typeof(j)=="Instance","Path did not resolve to a valid Instance.")
assert(j:IsA"TextBox","Resolved Instance is not a TextBox.")

j:CaptureFocus()
task.wait(0.05)

if i then
local k=pcall(function()
for k=1,#g do
d:SendTextInput(g:sub(k,k),nil,game)
task.wait(0.01)
end
end)

if not k and type(keypress)=="function"then
for l=1,#g do
local m=g:sub(l,l):upper()
local n=m:byte()
if n then
keypress(n)
task.wait(0.01)
if type(keyrelease)=="function"then
keyrelease(n)
end
end
end
end
else
j.Text=g
end

if h then
if i then
if type(keypress)=="function"then
keypress(0x0D)
task.wait(0.01)
if type(keyrelease)=="function"then
keyrelease(0x0D)
end
else
pcall(function()
d:SendKeyEvent(true,Enum.KeyCode.Return,false,game)
task.wait(0.01)
d:SendKeyEvent(false,Enum.KeyCode.Return,false,game)
end)
end
end
j:ReleaseFocus(true)
else
j:ReleaseFocus(false)
end

return{
status="success",
message="Successfully typed into TextBox."
}
end)

c:BindToType("click-button",function(e)
local f=e.path
local g=e.Action or e.action

local h
if typeof(f)=="string"then
h=loadstring("return "..f)()
else
h=f
end

assert(typeof(h)=="Instance","Path did not resolve to a valid Instance.")
assert(h:IsA"GuiButton","Resolved Instance is not a GuiButton (e.g., TextButton or ImageButton).")
assert(typeof(firesignal)=="function","Your executor does not support 'firesignal', which is required for this command.")

local i={"Activated","MouseButton1Down","MouseButton2Down","MouseButton1Click","MouseButton2Click"}

if g then
assert(table.find(i,g),"Invalid action provided. Valid actions are: "..table.concat(i,", "))
firesignal(h[g])
else
for j,k in pairs(i)do
pcall(function()firesignal(h[k])end)
end
end

return{
status="success",
message="Successfully fired click signals on Button."
}
end)
end end function a.h():typeof(__modImpl())local b=a.cache.h if not b then b={c=__modImpl()}a.cache.h=b end return b.c end end end

local b=__relapse_mcp_channel
if not game:IsLoaded()then game.Loaded:Wait()end
local c=getgenv()
local d="__relapse_mcp_"..b

if rawget(c,d)then return end

local e=cloneref or function(e)return e end
local f=e(game:GetService"HttpService")
local g=e(game:GetService"LogService")
local h=e(game:GetService"Players")
local i=e(game:GetService"MarketplaceService")
local j=e(game:GetService"RobloxReplicatedStorage")
local k=e(game:GetService"CoreGui")
local l=e(game:GetService"CorePackages")
local m=e(game:GetService"ScriptContext")
local n=e(Instance.new"VirtualInputManager")

local o=a.a()
local p={peers={},closed=false}
local q=RelapseChannel.new(b)
local r={Callbacks={},RawCallbacks={}}
function r.BindToType(s,t,u)s.Callbacks[t]=u end
function r.BindToTypeRaw(s,t,u)
s.Callbacks[t]=u
s.RawCallbacks[t]=true
end
local function send(s,t)
if p.closed or not s.Connected then return false end
local u=pcall(s.Send,s,t)


if not u then pcall(s.Close,s)end
return u
end
function r.Send(s,t,u)
if u then return send(u,t)end
for v,w in p.peers do
if w then send(v,t)end
end
return true
end
function r.HandleMessage(s,t,u)
if p.closed or p.peers[u]~=true then return end
if type(t)~="table"or type(t.type)~="string"or type(t.id)~="string"then return end
local v=s.Callbacks[t.type]
if not v then
send(u,{id=t.id,error="Unknown command: "..t.type})
return
end
task.spawn(function()
local w,x=pcall(v,t)
if not u.Connected or p.closed then return end
if not w then
send(u,{id=t.id,error=o.Error(x)})
elseif x~=nil then
local y=if s.RawCallbacks[t.type]then x else o.Format(x)
if type(y)~="string"then
send(u,{id=t.id,error="Handler returned an invalid text result."})
elseif#y>7340032 then
send(u,{id=t.id,error="Result exceeds the Relapse channel limit. Request a smaller range or result."})
else
send(u,{id=t.id,output=y})
end
end
end)
end

local function isScript(s)
return s:IsA"LuaSourceContainer"and
(not s:IsA"Script"or s.RunContext==Enum.RunContext.Client)and
not s.RobloxLocked and not s:IsDescendantOf(k)and
not s:IsDescendantOf(l)and not s:IsDescendantOf(m)
end
local s=a.b(){
HttpService=f,
IsScript=isScript,
Send=function(s,t)return r:Send(s,t)end,
Error=o.Error,
}
local t={
LogService=g,
MarketplaceService=i,
RobloxReplicatedStorage=j,
VirtualInputManager=n,
GetScriptByDebugId=s.GetScriptByDebugId,
DecompileScriptSource=s.DecompileScriptSource,
}
for u,v in{a.c()
,a.d()
,a.e()
,a.f()
,a.g()
,a.h()
,
}do v(t,r)end


local function close()
if p.closed then return end
p.closed=true
s.Stop()
q:Close()
pcall(function()n:Destroy()end)
rawset(c,d,nil)
end
q.Connected:Connect(function(u)
if p.closed then u:Close()return end
p.peers[u]=false
u.Disconnected:Connect(function()
p.peers[u]=nil
if not next(p.peers)then close()end
end)
u.MessageReceived:Connect(function(v)r:HandleMessage(v,u)end)
local v=h.LocalPlayer
local w="Unknown"
pcall(function()w=i:GetProductInfo(game.PlaceId).Name end)
if not send(u,{type="hello",client={
username=v and v.Name or"Unknown",
userId=v and v.UserId or 0,
placeId=game.PlaceId,jobId=game.JobId,placeName=w,
}})then return end
p.peers[u]=true
s.Start()
s.Sync(u)
end)
rawset(c,d,true)

task.delay(20,function()
if not next(p.peers)then close()end
end)