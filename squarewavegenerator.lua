#!/usr/bin/lua5.2
local debug = false
--[[ add one '-' here to enable debug output
debug = true
--]]
--[[
squarewavegenerator v0.4
wave/sound generator with multiple waveshapes, volume, sliding and duty cycle support

default behavior:
input: stdin
output: stdout
input format: stderr

command-line arguments:
squarewavegenerator args...
these arguments are possible:
 outputfile|output|of <outputfile>
  specifies a different output file than stdout
 mplayer|play
  plays output with a pipe to mplayer, passing any settings like samplerate automatically, only works on Linux with mplayer installed, forces endianness to little and format to 16-bit PCM
 quiet|q
  doesn't send any questions to stderr (still sends errors and progress %)
 noprogress|np
  no progress: doesn't write the progress message every second
 nointeractive|ni
  no interactive mode, doesn't read from stdin and only from command-line arguments, this automatically assumes all default values if they are not given on the command-line, instead of asking the user
 samplerate|sr <samplerate>
  set the samplerate, it will not be asked anymore in interactive mode if this is given
 gain|g <gain>
  set the gain, it will not be asked anymore in interactive mode if this is given
 endian <little|big>
  <little|big> must be exactly "little" or "big", or it will still be asked in interactive mode
 pcm
  set 16-bit signed PCM mode (default is 32-bit float according to IEEE754)
 wave|w <number> <property> <value>
  this sets the property with name <property> to <value> for the wave with the given number, if that wave didn't exist yet, it will be created, the wave numbers are completely unrelated to the numbers shown in interactive mode
  possible properties are:
   starttime|start <number>: the sample when this wave starts [1], if this ends with "s", it is multiplied by the sample rate
   endtime|end <number>: the sample when this wave ends, if this ends with "s", it is multiplied by the sample rate [if not the first wave, this is the ending time of the last wave, otherwise the sample rate]
   volumestart|vol|volstart <number>: the volume at the beginning of the wave [1]
   volumeend|volend <number>: the volume at the end of the wave [the same as volumestart, otherwise 1]
   volumeramp|volramp <function>: function that specifies the way this ramps [x, meaning linear]
    can also be "lin" or "exp", implying a linear or exponential growth
   shape <sine|square|sawtooth|triangle|noise>: must be exactly one of those (noise is white noise) [sine]
   frequencystart|freq|freqstart <number>: a number of Hertz at the start of the wave [440], you can also use note names like A4, here is the full syntax:
    the first letter is A to G (can also be lowercase)
    then come any number of #s and bs
    then comes the octave number
    the behaviour of any other syntax is undefined
   frequencyend|freqend <number>: same as frequencystart but for the end of the note [frequencystart or 440]
   frequencyramp|freqramp <function>: see volumeramp for an explanation
    this can also be "lin" or "exp"
   duty <number>: the same as dutystart
   dutystart <number>: number between 0 and 1 that describes the duty cycle of a square wave, has no effect if not a square wave [.5]
   dutyend <number>: same as dutystart but for the end [dutystart or .5]
   dutyramp <function>: describes the ramp from dutystart to dutyend, see volumeramp for explanation

sample rate (e.g. 44100)
gain (global volume) (useful 0 to 1, theoretical unlimited)
little/big endian (IEEE754 is little-endian)
number of wave events
for each wave:
starting time + ending time in samples
volume at start + end
if start and end volumes are not the same: ramping method
  user will be asked for a (mathematical) function f(x) that will be called from 0 to 1 and should return from 0 to 1, f(x)=x is linear
  standard math library functions are available as global
wave shape: sine/square/sawtooth/triangle/noise
if wave shape is not noise, frequency at start + end (in Hz)
  if start and end are not equal, function like previous for ramping method like volume above
if wave shape is square, duty cycle at start + end (0 to 1)
  if start and end are not equal, function like previous for ramping method like volume above
]]

local bit32 = require("bit32")
local io = require("io")
local math = require("math")
local os = require("os")
local string = require("string")

local nan = -(0/0)
local inf = 1/0

local notenames = {
 C = 0,
 D = 2,
 E = 4,
 F = 5,
 G = 7,
 A = 9,
 B = 11
}

local function floatstring(n)
  if tostring(n) == "0" then
    return string.char(0x00,0x00,0x00,0x00)
  elseif tostring(n) == "-0" then
    return string.char(0x80,0x00,0x00,0x00)
  elseif n == inf then
    return string.char(0x7f,0x80,0x00,0x00)
  elseif n == -inf then
    return string.char(0xff,0x80,0x00,0x00)
  elseif n == nan then
    return string.char(0x7f,0xff,0xff,0xff)
  elseif n == -nan then
    return string.char(0xff,0xff,0xff,0xff)
  else
    local sign = 0
    if n < 0 then
      sign = 128
    end
    local frac,exp = math.frexp(math.abs(n))
    frac = frac * 2 ^ 24
    exp = exp + 126 -- 127 ieee offset - 1 frexp() offset

    if exp > 255 then
      return string.char(bit32.bor(sign,0x7f),0x80,0,0)
    elseif exp < 0 then -- denormalized values need support
      return string.char(sign,0x7f,0xff,0xff)
    end

    return string.char(
      bit32.bor(sign,bit32.band(bit32.rshift(exp,1),0x7f)),
      bit32.bor(bit32.band(bit32.lshift(exp,7),0x80),bit32.band(bit32.rshift(frac,16),0x7f)),
      bit32.band(bit32.rshift(frac,8),0xff),
      bit32.band(frac,0xff)
    )
  end
end

local function pcmstring(n)
  if n < -1 then
    n = -1
  end
  if n >= 1 then
    n = 32767/32768
  end
  if n < 0 then
    n = n + 2 -- wraps -1 to 1 and 0 to 2=0
  end
  if n >= 2 then
    n = 0
  end
  n = math.floor(n * 32768)
  return string.char(bit32.rshift(n,8),bit32.band(n,0xff))
end

local function calcramp(func,time,mintime,maxtime,minval,maxval)
  local v = func((time - mintime) / (maxtime - mintime))
  return (1 - v) * minval + v * maxval
end

local args = {...}
local i = 1
local outputfile,quiet,nointeractive,noprogress,samplerate,gain,endian,pcm,nwaves
local waves = {}
local mplayeroptions = ""
local lastwavedefault = 0
while i <= #args do
  if args[i] == "outputfile" or args[i] == "output" or args[i] == "of" then
    outputfile = args[i + 1]
    i = i + 1
  elseif args[i] == "mplayer" or args[i] == "play" then
    outputfile = true
  elseif args[i] == "mplayeroptions" then
    mplayeroptions = mplayeroptions .. " " .. args[i + 1]
    i = i + 1
  elseif args[i] == "quiet" or args[i] == "q" then
    quiet = true
  elseif args[i] == "noprogress" or args[i] == "np" then
    noprogress = true
  elseif args[i] == "nointeractive" or args[i] == "ni" then
    nointeractive = true
  elseif args[i] == "samplerate" or args[i] == "sr" then
    samplerate = tonumber(args[i + 1])
    i = i + 1
  elseif args[i] == "gain" or args[i] == "g" then
    gain = tonumber(args[i + 1])
    i = i + 1
  elseif args[i] == "endian" then
    if args[i + 1] == "little" then
      endian = string.reverse
    elseif args[i + 1] == "big" then
      endian = function(s) return s end
    end
    i = i + 1
  elseif args[i] == "pcm" then
    pcm = true
  elseif args[i] == "wave" or args[i] == "w" then
    local n = tonumber(args[i + 1])
    if not n or n ~= math.floor(n) or n < 0 then
      io.stderr:write("error at argument #" .. i + 1 .. ": whole number expected\n")
      os.exit(-1)
    end
    if not waves[n] then
      waves[n] = {}
    end
    local property = args[i + 2]
    local value = args[i + 3]
    local nvalue = tonumber(value)
    local cnv = false -- check nvalue
    if property == "starttime" or property == "start" then
      if value:sub(-1,-1) == "s" then
        waves[n].starttime = tonumber(value:sub(1,-2)) * (samplerate or 44100)
	if not waves[n].starttime then
	  cnv = true
	end
      else
        waves[n].starttime = nvalue
        cnv = true
      end
    elseif property == "endtime" or property == "end" then
      if value:sub(-1,-1) == "s" then
        waves[n].endtime = tonumber(value:sub(1,-2)) * (samplerate or 44100)
	if not waves[n].endtime then
	  cnv = true
	end
      else
	waves[n].endtime = nvalue
	if nvalue then
	  if lastwavedefault then
	    if nvalue > lastwavedefault then
	      lastwavedefault = nvalue
	    end
	  else
	    lastwavedefault = nvalue
	  end
	end
	cnv = true
      end
    elseif property == "volumestart" or property == "vol" or property == "volstart" then
      waves[n].volumestart = nvalue
      cnv = true
    elseif property == "volumeend" or property == "volend" then
      waves[n].volumeend = nvalue
      cnv = true
    elseif property == "volumeramp" or property == "volramp" then
      waves[n].volumeramp = (load("return function(x) return " .. value .. " end","volumeramp","t",math) or function() io.stderr:write("error at argument #" .. i + 3 .. ": invalid function\n") os.exit(-1) end)()
    elseif property == "shape" then
      if value ~= "sine" and value ~= "square" and value ~= "sawtooth" and value ~= "triangle" and value ~= "noise" then
        io.stderr:write("error at argument #" .. i + 2 .. " (" .. (args[i + 2] or "<none>") .. ": illegal wave shape\n")
	os.exit(-1)
      end
      waves[n].shape = value
    elseif property == "frequencystart" or property == "freq" or property == "freqstart" then
      waves[n].frequencystart = value
    elseif property == "frequencyend" or property == "freqend" then
      waves[n].frequencyend = value
    elseif property == "frequencyramp" or property == "freqramp" then
--    waves[n].frequencyramp = (load("return function(x) return " .. value .. " end","volumeramp","t",math) or function() io.stderr:write("error at argument #" .. i + 3 .. ": invalid function\n") os.exit(-1) end)()
      waves[n].frequencyramp = value
    elseif property == "dutystart" or property == "duty" then
      waves[n].dutystart = nvalue
      cnv = true
    elseif property == "dutyend" then
      waves[n].dutyend = nvalue
      cnv = true
    elseif property == "dutyramp" then
      waves[n].dutyramp = (load("return function(x) return " .. value .. " end","volumeramp","t",math) or function() io.stderr:write("error at argument #" .. i + 3 .. ": invalid function\n") os.exit(-1) end)()
    else
      io.stderr:write("error at argument #" .. i + 1 .. " (" .. (args[i + 1] or "<none>") .. "): illegal property name\n")
      os.exit(-1)
    end
    if cnv and not nvalue then
      io.stderr:write("error at argument #" .. i + 3 .. " (" .. (args[i + 3] or "<none>") .. "): illegal number\n")
      os.exit(-1)
    end
    i = i + 3
  else
    io.stderr:write("error at argument #" .. i .. " (" .. (args[i] or "<none>") .. "): illegal option\n")
    os.exit(-1)
  end
  i = i + 1
end

local lastwave = 0
for i,v in pairs(waves) do
  if i > lastwave then
    lastwave = i
  end
end

if debug then
  print("outputfile",outputfile)
end
if outputfile and not(outputfile == true) then
  outputfile,reason = io.open(outputfile,"wb")
  if not outputfile then
    io.stderr:write("error opening file for writing: " .. reason .. "\n")
    os.exit(-1)
  end
  outputfile:setvbuf("full")
elseif not(outputfile == true) then
  outputfile = io.stdout
  if not quiet then
    io.stderr:write("warning: output will be to stdout\n")
  end
else
  pcm = true
  endian = string.reverse
  if not quiet then
    io.stderr:write("warning: output will be played to mplayer\n")
  end
end

if nointeractive then
  samplerate = samplerate or 44100
  gain = gain or 1
  endian = endian or string.reverse
  pcm = pcm or false
else
  if not samplerate then
    if not quiet then
      io.stderr:write("sample rate (number samples/second) [44100]: ")
    end
    samplerate = tonumber(io.read()) or 44100
  end
  if not gain then
    if not quiet then
      io.stderr:write("gain (number 0 to 1) [1]: ")
    end
    gain = tonumber(io.read()) or 1
  end
  if not endian then
    if not quiet then
      io.stderr:write("little/big endian [little/big] [little]: ")
    end
    endian = string.reverse
    if io.read():lower() == "big" then
      function endian(a)
	return a
      end
    end
  end
  if not pcm then
    if not quiet then
      io.stderr:write("32-bit float or 16-bit pcm [float/pcm] [float]: ")
    end
    pcm = io.read()
    if pcm == "pcm" then
      pcm = true
    end
  end
end
local totalwaves = 0
if not nointeractive then
  if not quiet then
    io.stderr:write("number of wave events (whole number) [1]: ")
  end
  totalwaves = tonumber(io.read()) or 1
end
for i=1,totalwaves + lastwave do
  local existed = false
  if i <= lastwave and waves[i] then
    existed = true
  end
  if i <= lastwave and not waves[i] then
  else
    if not existed then
      waves[i] = {}
    end
    if not existed and not quiet then
      io.stderr:write("wave #" .. i - lastwave .. "\nstarting time (number samples) [1]: ")
    end
    if existed then
      waves[i].starttime = waves[i].starttime or 1
    else
      local t = io.read()
      if t:sub(-1,-1) == "s" then
        waves[i].starttime = tonumber(t:sub(1,-2)) * samplerate
      else
	waves[i].starttime = tonumber(t)
      end
      waves[i].starttime = waves[i].starttime or 1
    end
    if not existed and not quiet then
      io.stderr:write("ending time (number samples) [" .. (lastwavedefault > 0 and lastwavedefault or waves[i].starttime + samplerate - 1) .. "]: ")
    end
    if existed then
      waves[i].endtime = waves[i].endtime or lastwavedefault > 0 and lastwavedefault or waves[i].starttime + samplerate - 1
    else
      local t = io.read()
      if t:sub(-1,-1) == "s" then
        waves[i].endtime = tonumber(t:sub(1,-2)) * samplerate
      else
        waves[i].endtime = tonumber(t)
      end
      waves[i].endtime = waves[i].endtime or lastwavedefault > 0 and lastwavedefault or waves[i].starttime + samplerate - 1
    end
    if waves[i].endtime > lastwavedefault then
      lastwavedefault = waves[i].endtime
    end
    if not existed and not quiet then
      io.stderr:write("volume at start (number -1 to 1) [1]: ")
    end
    waves[i].volumestart = existed and (waves[i].volumestart or 1) or tonumber(io.read()) or 1
    if not existed and not quiet then
      io.stderr:write("volume at end (number -1 to 1) [" .. waves[i].volumestart .. "]: ")
    end
    waves[i].volumeend = existed and (waves[i].volumeend or waves[i].volumestart) or tonumber(io.read()) or waves[i].volumestart
    if waves[i].volumestart ~= waves[i].volumeend then
      if not existed and not quiet then
	io.stderr:write("volume ramp [f(x)=x]: f(x)=")
      end
      local func
      if not existed then
	func = io.read()
	if func == "" then
	  func = "x"
	end
	waves[i].volumeramp = load("return function(x) return " .. func .. " end","volumeramp","t",math)()
      elseif not waves[i].volumeramp then
	waves[i].volumeramp = function(x) return x end
      end
    else
      waves[i].volumeramp = function() return 0 end
    end
    if not existed then
      if not quiet then
	io.stderr:write("wave shape [sine/square/sawtooth/triangle/noise] [sine]: ")
      end
      waves[i].shape = io.read()
    end
    if not(waves[i].shape == "sine" or waves[i].shape == "square" or waves[i].shape == "sawtooth" or waves[i].shape == "triangle" or waves[i].shape == "noise") then
      if not quiet and shape then
        io.stderr:write("illegal wave shape \"" .. waves[i].shape .. "\", selecting default \"sine\"\n")
      end
      waves[i].shape = "sine"
    end
    if waves[i].shape ~= "noise" then
      if not existed and not quiet then
	io.stderr:write("frequency at start (number Hz or MIDI name) [440]: ")
      end
      waves[i].frequencystart = existed and (waves[i].frequencystart or 440) or io.read()
      if waves[i].frequencystart == "" then
        waves[i].frequencystart = 440
      end
      if not tonumber(waves[i].frequencystart) then
        local full = waves[i].frequencystart
        local note = notenames[full:sub(1,1):upper()] or notenames.A
	local octave = tonumber(full:match("%d+$")) or 4 -- all digits at the end of the string
	for i=2,full:len() do
	  if full:sub(i,i) == "#" then
	    note = note + 1
	  end
	  if full:sub(i,i) == "b" then
	    note = note - 1
	  end
	end
	waves[i].frequencystart = 440 * 2 ^ ((note - 69) / 12 + octave + 1)
      else
        waves[i].frequencystart = tonumber(waves[i].frequencystart)
      end
      if not existed and not quiet then
	io.stderr:write("frequency at end (number Hz or MIDI name) [" .. waves[i].frequencystart .. "]: ")
      end
      waves[i].frequencyend = existed and (waves[i].frequencyend or waves[i].frequencystart) or io.read()
      if waves[i].frequencyend == "" then
        waves[i].frequencyend = waves[i].frequencystart
      end
      if not tonumber(waves[i].frequencyend) then
        local full = waves[i].frequencyend
        local note = notenames[full:sub(1,1):upper()] or notenames.A
	local octave = tonumber(full:match("%d+$")) or 4 -- all digits at the end of the string
	for i=2,full:len() do
	  if full:sub(i,i) == "#" then
	    note = note + 1
	  end
	  if full:sub(i,i) == "b" then
	    note = note - 1
	  end
	end
	waves[i].frequencyend = 440 * 2 ^ ((note - 69) / 12 + octave + 1)
      else
        waves[i].frequencyend = tonumber(waves[i].frequencyend)
      end
      if waves[i].frequencystart ~= waves[i].frequencyend then
        local func
	if not existed then
	  if not quiet then
	    io.stderr:write("frequency ramp [f(x)=x]: f(x)=")
	  end
	  func = io.read()
	else
	  func = waves[i].frequencyramp or "lin"
	end
	if func == "" or not func then
	  func = "lin"
	end
	if func == "lin" then
	  waves[i].frequencyramp = function(x) return x end
--	  waves[i].frequencyend = (waves[i].frequencystart + waves[i].frequencyend) / 2
	elseif func == "exp" then
	  local e = math.exp(1)
	  local ln = math.log(e - 1)
	  waves[i].frequencyramp = function(x) return math.exp(x - ln) - 1 / (e - 1) end
--	  waves[i].frequencyend = math.sqrt(waves[i].frequencystart * waves[i].frequencyend)
	else
	  waves[i].frequencyramp = load("return function(x) return " .. func .. " end","frequencyramp","t",math)()
	end
      else
	waves[i].frequencyramp = function() return 0 end
      end
    else
      waves[i].frequencystart = 0
      waves[i].frequencyend = 0
      waves[i].frequencyramp = function(x) return x end
    end
    if waves[i].shape == "square" then
      if not existed and not quiet then
	io.stderr:write("duty cycle at start (number 0 to 1) [.5]: ")
      end
      waves[i].dutystart = existed and (waves[i].dutystart or .5) or tonumber(io.read()) or .5
      if not existed and not quiet then
	io.stderr:write("duty cycle at end (number 0 to 1) [" .. waves[i].dutystart .. "]: ")
      end
      waves[i].dutyend = existed and (waves[i].dutyend or waves[i].dutystart) or tonumber(io.read()) or waves[i].dutystart
      if waves[i].dutystart ~= waves[i].dutyend then
	if not existed then
	  if not quiet then
	    io.stderr:write("duty ramp [f(x)=x]: f(x)=")
	  end
	  local func = io.read()
	  if func == "" then
	    func = "x"
	  end
	  waves[i].dutyramp = load("return function(x) return " .. func .. " end","dutyramp","t",math)()
	elseif not waves[i].dutyramp then
	  waves[i].dutyramp = function(x) return x end
	end
      else
	waves[i].dutyramp = function() return 0 end
      end
    end
    waves[i].totaltime = waves[i].endtime - waves[i].starttime + 1
  end
end

if outputfile == true then
  outputfile,reason = io.popen("mplayer -demuxer rawaudio -rawaudio channels=1:rate=" .. samplerate .. ":samplesize=2 -really-quiet" .. mplayeroptions .. " -","w")
  if not outputfile then
    io.stderr:write("error opening mplayer pipe: " .. reason .. "\n")
    os.exit(-1)
  end
end

if not quiet then
  io.stderr:write("total file size is " .. lastwavedefault .. " samples or " .. lastwavedefault * (pcm and 2 or 4) .. " bytes or " .. lastwavedefault * (pcm and 2 or 4) / 1048576 .. " megabytes\n")
end

if debug then
  print("[DEBUG] wave list:")
  for i=1,totalwaves + lastwave do
    print("wave",i)
    for k,v in pairs(waves[i]) do
      print("",k,v)
    end
  end
end

for i=1,lastwavedefault do
  if not noprogress and i % samplerate == 0 then
    io.stderr:write("\rsample " .. i .. "/" .. lastwavedefault .. " (" .. math.floor(i / lastwavedefault * 100) .. "%)")
  end

  local total = 0
  for j=1,totalwaves + lastwave do
    if waves[j] and waves[j].starttime <= i and waves[j].endtime >= i then
      if debug then
        print("calculating wave",j,"at sample",i)
      end
      if waves[j].previousvalue and (math.abs(waves[j].previousvalue) == nan or math.abs(waves[j].previousvalue) == inf) then
        if debug then
	  print("set previousvalue to nil")
	end
        waves[j].previousvalue = nil
      end
      local volume = calcramp(waves[j].volumeramp,i,waves[j].starttime,waves[j].endtime,waves[j].volumestart,waves[j].volumeend)
      local frequency = waves[j].frequencyramp and calcramp(waves[j].frequencyramp,i,waves[j].starttime,waves[j].endtime,waves[j].frequencystart,waves[j].frequencyend) or waves[j].frequencystart
      local duty = waves[j].dutyramp and calcramp(waves[j].dutyramp,i,waves[j].starttime,waves[j].endtime,waves[j].dutystart,waves[j].dutyend) or waves[j].dutystart
--    local progress = waves[j].frequencystart and ((i - waves[j].starttime) * frequency / samplerate + .25) % 1 -- inverse sawtooth from 0 to 1, starts at .25
      local progress = frequency and (waves[j].previousvalue and frequency / samplerate + waves[j].previousvalue or (i - waves[j].starttime) * frequency / samplerate) % 1
      waves[j].previousvalue = progress

      if debug then
        print("sample",i,"wave",j,"freq",frequency,"freqramp",calcramp(waves[j].frequencyramp,i,waves[j].starttime,waves[j].endtime,0,1),"progress",progress)
      end

      if waves[j].shape == "noise" then
        total = total + (math.random() * 2 - 1) * volume
      elseif waves[j].shape == "sine" then
        total = total + math.sin(progress * 2 * math.pi) * volume
      elseif waves[j].shape == "square" then
        total = total + (progress < duty and 1 or -1) * volume
      elseif waves[j].shape == "sawtooth" then
        total = total + (1 - progress * 2) * volume
      elseif waves[j].shape == "triangle" then
        total = total + (progress < .25 and progress or progress > .75 and progress - 1 or .5 - progress) * 4
      end
    end
  end
  outputfile:write(endian((pcm and pcmstring or floatstring)(total * gain)))
end

outputfile:flush()
outputfile:close()

if not noprogress then
  io.stderr:write("\n")
end
