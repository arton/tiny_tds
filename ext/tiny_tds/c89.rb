# coding: utf-8
require 'tempfile'
require 'fileutils'
class C89AdhocParser

  class Block
    def initialize
      @declare = []
      @body = []
      @rwrapper = false
      @cwrapper = false
      @cuserdata = false
    end
    attr_accessor :declare, :rwrapper, :cwrapper, :cuserdata
    def add(blk)
      @body.push blk
    end
    def flush(w)
      w.puts '  tinytds_result_wrapper *rwrap;' if @rwrapper
      w.puts '  tinytds_client_wrapper *cwrap;' if @cwrapper      
      w.puts '  tinytds_client_userdata *userdata;' if @cuserdata
      @declare.each do |x|
        w.puts x
      end
      @body.each do |x|
        if Block === x
          x.flush(w)
        else
          w.puts x
        end
      end
    end
  end
  
  def initialize
    @cfunc = nil
    @cblk = nil
    @idle = Proc.new do |x, w|
      w.write x
      if x =~ /\A\s*[a-zA-Z]\w*\s+(?:[a-zA-Z]\w*\s+)?\w+\([a-zA-Z0-9_*, ]*\)\s*{\s*\z/
        @cblk = Block.new
        @cfunc = [@cblk]
        @infun
      else
        @idle
      end
    end
    @infun = Proc.new do |x, w|
      if x=~ /GET_RESULT_WRAPPER/
        x.sub!(/GET_RESULT_WRAPPER\(([^)]+)/, 'Data_Get_Struct(\1, tinytds_result_wrapper, rwrap')
        @cblk.rwrapper = true
      elsif x =~ /GET_CLIENT_WRAPPER/
        x.sub!(/GET_CLIENT_WRAPPER\(([^)]+)/, 'Data_Get_Struct(\1, tinytds_client_wrapper, cwrap')
        @cblk.cwrapper = true
      elsif x =~ /GET_CLIENT_USERDATA/
        x.sub!(/GET_CLIENT_USERDATA\(([^)]+)/, 'userdata = (tinytds_client_userdata *)dbgetuserdata(\1')
        @cblk.cuserdata = true  
      end
      if x =~ /\A}\s*\z/
        @cblk.add x   
        @cblk.flush w
        @idle
      else
        if x =~ /\A\s*}\s*(?:else(?:\s+if\s*\([^)]+\))?\s*({))?\s*\Z/
          @cblk = @cfunc.pop
          @cblk.add x
          if $1
            blk = Block.new
            @cblk.add blk
            @cfunc.push @cblk
            @cblk = blk
          end
        elsif x =~ /\A.+{\s*\z/
          @cblk.add x          
          blk = Block.new
          @cblk.add blk
          @cfunc.push @cblk
          @cblk = blk
        else
          if x =~ /\A(\s*)((?:(?:(?:un)?signed|long)\s+)?\w+\*?)\s+(\*?\w+(?:\[[^]]*\])?)(\s*=.+)\Z/
            @cblk.declare << "#{$1}#{$2} #{$3};"
            @cblk.add "#{$1}#{$3[0] == '*' ? $3[1..-1] : $3}#{$4}"
          elsif x =~ /\A(?:\s*)((?:(?:(?:un)?signed|long)\s+)?\w+\*?)\s+(\*?\w+(?:\[[^]]*\])?)\s*;\s*\z/ && $1 != 'return'
            @cblk.declare << x
          else
            @cblk.add x.rstrip
          end  
        end
        @infun
      end
    end
    @current = @idle
  end
  
  def parse(r, w)
    r.each_line do |line|
      @current = @current.call(line, w)
    end
  end
  
  def flush(w)
    @declare.last.each do |line|
      w.puts line
    end
    @declare.pop
    @body.last.each do |line|
      w.puts line
    end
    @body.pop
  end
end


if __FILE__ == $0
  ARGV.each do |x|
    fout = Tempfile.new('c89adfoc')
    File.open(x, 'r') do |fin|
      C89AdhocParser.new.parse fin, fout
    end
    fout.close(false)
    FileUtils.mv x, "#{x}.bak"
    FileUtils.mv fout.path, x
  end
end
