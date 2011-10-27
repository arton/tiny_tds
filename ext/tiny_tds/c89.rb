# coding: utf-8
require 'tempfile'
require 'fileutils'
class C89AdhocParser

  class Block
    def initialize
      @declare = []
      @body = []
    end
    attr_accessor :declare
    def add(blk)
      @body.push blk
    end
    def flush(w)
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
  
  class Replacement
    def initialize(start, rep, stop)
      @start = start
      @rep = rep
      @stop = stop
    end
    def start?(s, b, w)
      if s =~ @start
        @rep.call(s, b, w)
      end
    end
    def stop?(s, b, w)
      s =~ @stop
    end
  end
  
  REPS = [
    Replacement.new(/\A#ifdef HAVE_RUBY_ENCODING_H/,
                    Proc.new do |s, b, w|
                      w.write s
                      w.write <<D
  VALUE encoded_str_new(_data, _len, rwrap) {
    VALUE _val = rb_str_new((char *)_data, (long)_len); 
    rb_enc_associate(_val, rwrap->encoding); 
    return _val;
  }
  VALUE encoded_str_new2(_data2, rwrap) {
    VALUE _val = rb_str_new2((char *)_data2);
    rb_enc_associate(_val, rwrap->encoding);
    return _val;
  }
  #define ENCODED_STR_NEW(_data, _len) encoded_str_new(_data, _len, rwrap)
  #define ENCODED_STR_NEW2(_data2) encoded_str_new2(_data2, rwrap)
#else
D
                      true
                    end,
                    /\A#else/,
                    ),
    Replacement.new(/\A\s*GET_RESULT_WRAPPER/,
                    Proc.new do |s, b, w|
                      s.sub!(/GET_RESULT_WRAPPER\(([^)]+)/, 'Data_Get_Struct(\1, tinytds_result_wrapper, rwrap')
                      b.declare << '  tinytds_result_wrapper *rwrap;'
                      nil
                    end,
                    nil),
    Replacement.new(/\A\s*GET_CLIENT_WRAPPER/,
                    Proc.new do |s, b, w|
                      s.sub!(/GET_CLIENT_WRAPPER\(([^)]+)/, 'Data_Get_Struct(\1, tinytds_client_wrapper, cwrap')
                      b.declare << '  tinytds_client_wrapper *cwrap;'
                      nil
                    end,
                    nil),
    Replacement.new(/\A\s*GET_CLIENT_USERDATA/,
                    Proc.new do |s, b, w|
                      s.sub!(/GET_CLIENT_USERDATA\(([^)]+)/, 'userdata = (tinytds_client_userdata *)dbgetuserdata(\1')
                      b.declare << '  tinytds_client_userdata *userdata;'
                      nil
                    end,
                    nil),
         ]

  def initialize
    @cfunc = nil
    @cblk = nil
    @repl = nil
    @idle = Proc.new do |x, w|
      if check_replacements(x, w)
        @idle
      else  
        w.write x
        if x =~ /\A\s*[a-zA-Z]\w*\s+(?:[a-zA-Z]\w*\s+)?\w+\([a-zA-Z0-9_*, ]*\)\s*{\s*\z/
          @cblk = Block.new
          @cfunc = [@cblk]
          @infun
        else
          @idle
        end
      end
    end
    
    @infun = Proc.new do |x, w|
      if check_replacements(x, w)
        @infun
      elsif x =~ /\A}\s*\z/
        @cblk.add x   
        @cblk.flush w
        @idle
      else
        if x =~ /\A\s*}\s*(?:else(?:\s+if\s*\([^)]+\))?\s*({))?\s*\Z/
          @cblk = @cfunc.pop
          @cblk.add x
          if $1
            new_block
          end
        elsif x =~ /\A.+{\s*\z/
          @cblk.add x    
          new_block
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

  def new_block
    blk = Block.new
    @cblk.add blk
    @cfunc.push @cblk
    @cblk = blk
  end
  
  def check_replacements(x, w)
    if @repl
      if @repl.stop?(x, @cblk, w)
        @repl = nil
        return true
      end
    else
      @repl = REPS.find { |e| e.start?(x, @cblk, w) }
    end
    @repl
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
