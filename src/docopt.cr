module Docopt
  class DocoptException < Exception
  end

  class DocoptLanguageError < DocoptException
  end

  class DocoptExit < DocoptException
    @@usage = ""

    def self.usage=(u : String)
      @@usage = u
    end

    def self.usage
      @@usage
    end
  end

  class Tokens
    @internal : Array(String) = [] of String
    property :error
    @error : (DocoptExit.class | DocoptLanguageError.class)

    def initialize(@error : (DocoptExit.class | DocoptLanguageError.class) = DocoptExit)
      super()
    end

    delegate :<<, to: @internal
    delegate :[], to: @internal
    delegate size, to: @internal
    delegate delete_at, to: @internal
    delegate join, to: @internal
    delegate map, to: @internal

    def self.from_pattern(source : String) : Tokens
      ret = Tokens.new(DocoptExit)
      source.gsub(/([\[\]\(\)\|]|\.\.\.)/) { |_, m| " #{m[1]} " }.split.each do |tok|
        ret << tok
      end
      ret.error = DocoptLanguageError
      ret
    end

    def self.from_array(arr : Array(String)) : Tokens
      ret = Tokens.new
      arr.each do |e|
        ret << e
      end
      ret
    end

    def move : String | Nil
      size > 0 ? delete_at(0) : nil
    end

    def current : String | Nil
      size > 0 ? self[0] : nil
    end
  end

  abstract class Pattern
    getter :children

    def initialize
      @children = nil.as(Array(Pattern) | Nil)
    end

    def ==(other : Pattern) : Bool
      to_s == other.to_s
    end

    def inspect(io)
      io << to_s
    end

    def hash
      to_s.hash
    end

    def fix : Pattern
      fix_identities
      fix_repeating_arguments
      self
    end

    def fix_identities(uniq = nil) : Pattern
      # Make pattern-tree tips point to same object if they are equal.
      if @children.nil?
        return self
      end
      if uniq.nil?
        uniq = flat.uniq
      end
      uniq_ = uniq.as Array(Pattern)
      children = @children.as Array(Pattern)
      children.each_with_index do |child, i|
        if child.children.nil?
          raise "#{child} not in #{uniq}" if !uniq_.includes? child
          children[i] = uniq_[uniq_.index(child).as Int32]
        else
          child.fix_identities(uniq_)
        end
      end
      self
    end

    def fix_repeating_arguments : Pattern
      # Fix elements that should accumulate/increment values.
      (either.children.as Array(Pattern)).map { |c| c.children.as Array(Pattern) }.each do |case_|
        case_.select { |c| case_.count(c) > 1 }.map do |e|
          if e.class == Argument || e.class == Option && (e.as Option).argcount > 0
            e_ = (e.as(Argument | Option))
            if e_.value.nil?
              e_.value = [] of String
            elsif !e_.value.is_a? Array
              e_.value = (e_.value.as String).split
            end
          end
          if e.class == Command || e.class == Option && (e.as Option).argcount == 0
            (e.as(Command | Option)).value = 0
          end
        end
      end
      self
    end

    def either : Either
      result = [] of Array(Pattern)
      groups = [[self.as Pattern]].as Array(Array(Pattern))
      while groups.size > 0
        children = groups.delete_at 0
        types = children.map(&.class)
        if types.includes? Either
          either = children.select { |c| c.class == Either }[0].as Either
          children.delete_at(children.index(either).as Int32)
          (either.children.as Array(Pattern)).each do |c|
            groups << [c] + children
          end
        elsif types.includes? Required
          required = children.select { |c| c.class == Required }[0].as Required
          children.delete_at(children.index(required).as Int32)
          groups << ((required.children.as Array(Pattern)) + children)
        elsif types.includes? Optional
          optional = children.select { |c| c.class == Optional }[0].as Optional
          children.delete_at(children.index(optional).as Int32)
          groups << ((optional.children.as Array(Pattern)) + children)
        elsif types.includes? AnyOptions
          optional = children.select { |c| c.class == AnyOptions }[0].as AnyOptions
          children.delete_at(children.index(optional).as Int32)
          groups << ((optional.children.as Array(Pattern)) + children)
        elsif types.includes? OneOrMore
          oneormore = children.select { |c| c.class == OneOrMore }[0].as OneOrMore
          children.delete_at(children.index(oneormore).as Int32)
          groups << ((oneormore.children.as Array(Pattern))*2 + children)
        else
          result << children
        end
      end
      Either.new(result.map { |e| Required.new(e).as Pattern })
    end

    abstract def flat(*types)

    abstract def match(left : Array(Pattern), collected : (Nil | Array(Pattern)) = nil) : Tuple(Bool, Array(Pattern), Array(Pattern))
    #  return false, left, ([] of Pattern)
    # end
  end

  abstract class LeafPattern < Pattern
    getter :name
    property :value
    @name : (String | Nil)
    @value : (Nil | String | Int32 | Bool | Array(String))

    def initialize(@name, @value = nil)
      @children = nil.as(Array(Pattern) | Nil)
    end

    def to_s
      "#{self.class.to_s.split("::")[-1]}(#{@name}, #{@value})"
    end

    def flat(*types)
      if types.size == 0 || types.includes? self.class
        return [self.as Pattern]
      end
      [] of Pattern
    end

    def match(left : Array(Pattern), collected : (Nil | Array(Pattern)) = nil) : Tuple(Bool, Array(Pattern), Array(Pattern))
      # def match(left, collected = nil)
      # @TODO
      collected = [] of Pattern if collected.nil?
      collected_ = collected.as Array(Pattern)
      pos, match = single_match(left)
      if match.nil?
        return false, left, collected_
      end
      pos_ = pos.as Int32
      match_ = match.as LeafPattern
      left_ = left[0, pos_] + left[pos_ + 1, left.size]
      same_name = collected_.select { |a| a.is_a?(LeafPattern) && a.name == @name }
      if Int32 == @value.class || Array(String) == @value.class
        if @value.class == Int32
          increment = 1
          if same_name.size == 0
            match_.value = increment
            return true, left_, collected_ + ([match_.as Pattern])
          end
          value = (same_name[0].as LeafPattern).value.as Int32
          value += increment
          (same_name[0].as LeafPattern).value = value
          return true, left_, collected_
        else
          increment = match_.value.class == String ? ([match_.value.as String]) : (match_.value.as Array(String))
          if same_name.size == 0
            match_.value = increment
            return true, left_, collected_ + ([match_.as Pattern])
          end
          value = (same_name[0].as LeafPattern).value.as Array(String)
          value.concat increment
          (same_name[0].as LeafPattern).value = value
          return true, left_, collected_
        end
      end
      return true, left_, collected_ + ([match_.as Pattern])
    end

    abstract def single_match(left)
  end

  abstract class BranchPattern < Pattern
    property :children

    def initialize(children : Array(Pattern))
      @children = children
    end

    def to_s
      children = @children.as Array(Pattern)
      "#{self.class.to_s.split("::")[-1]}(#{children.map(&.to_s).join ", "})"
    end

    def flat(*types)
      if types.includes? self.class
        return [self.as Pattern]
      end
      ret = [] of Pattern
      children = @children.as Array(Pattern)
      children.each do |c|
        c.flat(*types).each do |p|
          ret << p
        end
      end
      ret
    end
  end

  class Required < BranchPattern
    def match(left : Array(Pattern), collected : (Nil | Array(Pattern)) = nil) : Tuple(Bool, Array(Pattern), Array(Pattern))
      # def match(left, collected = nil)
      collected = [] of Pattern if collected.nil?
      l = left
      c = collected.as Array(Pattern)
      ch = @children.as Array(Pattern)
      ch.each do |pat|
        matched, l, c = pat.match(l, c)
        if !matched
          return false, left, (collected.as Array(Pattern))
        end
      end
      return true, l, c
    end
  end

  class Optional < BranchPattern
    def match(left : Array(Pattern), collected : (Nil | Array(Pattern)) = nil) : Tuple(Bool, Array(Pattern), Array(Pattern))
      # def match(left, collected = nil)
      collected = [] of Pattern if collected.nil?
      ch = @children.as Array(Pattern)
      ch.each do |pat|
        _, left, collected = pat.match(left, collected)
      end
      return true, left, collected
    end
  end

  class AnyOptions < Optional
  end

  class Argument < LeafPattern
    def single_match(left)
      left.each_with_index do |pat, n|
        if pat.is_a? Argument
          return n, Argument.new(@name, pat.value)
        end
      end
      return nil, nil
    end

    def self.parse(source)
      name = source[/(<\S*?>)/]
      m = source.match(/\[default: (.*)\]/i)
      value = nil
      if m
        value = m[0]
      end
      typeof(self).new name, value
    end
  end

  class Command < Argument
    def initialize(@name, @value = false)
      super
    end

    def single_match(left)
      left.each_with_index do |pat, n|
        if pat.is_a?(Argument)
          if pat.value == @name
            return n, Command.new @name, true
          else
            break
          end
        end
      end
      return nil, nil
    end
  end

  class OneOrMore < BranchPattern
    def match(left : Array(Pattern), collected : (Nil | Array(Pattern)) = nil) : Tuple(Bool, Array(Pattern), Array(Pattern))
      # def match(left, collected = nil)
      ch = @children.as Array(Pattern)
      raise "#{ch}.size != 1" if ch.size != 1
      collected = [] of Pattern if collected.nil?
      l = left
      c = collected
      l_ = nil
      matched = true
      times = 0
      while matched
        matched, l, c = ch[0].match(l, c)
        times += 1 if matched
        if l_ == l
          break
        end
        l_ = l
      end
      if times >= 1
        return true, l, c
      end
      return false, left, collected
    end
  end

  class Either < BranchPattern
    def match(left : Array(Pattern), collected : (Nil | Array(Pattern)) = nil) : Tuple(Bool, Array(Pattern), Array(Pattern))
      # def match(left, collected = nil)
      collected = [] of Pattern if collected.nil?
      outcomes = [] of Tuple(Bool, Array(Pattern), Array(Pattern))
      ch = @children.as Array(Pattern)
      ch.each do |pat|
        matched, _, _ = outcome = pat.match(left, collected)
        if matched
          outcomes << outcome
        end
      end
      if outcomes.size > 0
        return outcomes.min_by(&.[1].size)
      end
      return false, left, collected
    end
  end

  class Option < LeafPattern
    getter :short, :long, :argcount
    property :value

    def initialize(@short : (String | Nil) = nil, @long : (String | Nil) = nil, @argcount = 0, value = false)
      raise "argcount not in [0,1]" if argcount != 0 && argcount != 1
      value = (value == false && argcount > 0) ? nil : value
      if !long.nil?
        name = long
      elsif !short.nil?
        name = short
      else
        raise "short and long are all nil"
      end
      super(name, value)
    end

    def self.parse(option_description)
      short, long, argcount, value = nil, nil, 0, false
      options, description = option_description.strip.split("  ", limit: 2)
      options = options.gsub(',', ' ').gsub('=', ' ')
      options.split.each do |tok|
        if tok.starts_with? "--"
          long = tok
        elsif tok.starts_with? "-"
          short = tok
        else
          argcount = 1
        end
      end
      if argcount
        if description =~ /\[default: (.*)\]/i
          value = $1
        else
          value = nil
        end
      end
      Option.new short, long, argcount, value
    end

    def single_match(left)
      left.each_with_index do |pat, n|
        if pat.is_a?(LeafPattern) && name == pat.name
          return n, pat
        end
      end
      return nil, nil
    end

    def to_s
      "Option(#{@short},#{@long},#{@argcount},#{@value})"
    end
  end

  def self.parse_section(name, source)
    ret = [] of String
    source.scan /^([^\n]*#{name}[^\n]*\n?(?:[ \t].*?(?:\n|$))*)/im do |_|
      ret << $1.strip
    end
    ret
  end

  def self.parse_defaults(doc) : Array(Option)
    defaults = [] of Option
    parse_section("options:", doc).each do |s|
      _, s = s.split(':', limit: 2)
      split = ("\n" + s).split /\n[ \t]*(-\S+?)/
      split = split[1, split.size]
      split.each_slice(2) do |x|
        s = x[0] + x[1]
        if s.starts_with? "-"
          defaults << Option.parse s
        end
      end
    end
    defaults
  end

  def self.formal_usage(section)
    _, section = section.split(":", limit: 2)
    pu = section.split
    "(" + pu[1, pu.size].map { |x| x == pu[0] ? ") | (" : x }.join(" ") + ")"
  end

  def self.parse_long(tokens, options) : Array(Pattern)
    tok = tokens.move.as String
    long_value = tok.split("=", limit: 2)
    long = long_value[0]
    raise "long pattern should start with '--'" if !long.starts_with? "--"
    value = long_value.size <= 1 ? nil : long_value[1]
    similar = options.select { |o| o.long == long }
    if tokens.error == DocoptExit && similar.size == 0
      similar = options.select { |o| (o.long.as String).starts_with? long }
    end
    if similar.size > 1
      raise tokens.error.new "#{long} is not a uniq prefix: #{similar.map(&.long).join(", ")}?"
    elsif similar.size < 1
      argcount = long_value.size > 1 ? 1 : 0
      o = Option.new nil, long, argcount
      options << o
      if tokens.error == DocoptExit
        o = Option.new nil, long, argcount, (argcount > 0 ? value : true)
      end
    else
      o = Option.new similar[0].short, similar[0].long, similar[0].argcount, similar[0].value
      if o.argcount == 0
        raise tokens.error.new("#{o.long} must not have an argument") if !value.nil?
      else
        if value.nil?
          raise tokens.error.new "#{o.long} requires argument" if [nil, "--"].includes? tokens.current
          value = tokens.move
        end
      end
      if tokens.error == DocoptExit
        o.value = value.nil? ? true : value
      end
    end
    [o.as Pattern]
  end

  def self.parse_shorts(tokens, options) : Array(Pattern)
    # shorts ::= '-' ( chars )* [ [ ' ' ] chars ] ;
    token = tokens.move.as String
    raise "short pattern should start swith -" if !(token.starts_with?("-") && !token.starts_with?("--"))
    left = token.gsub(/^\-+/, "")
    parsed = [] of Pattern
    while left != ""
      short, left = "-" + left[0], left[1, left.size]
      similar = options.select { |o| o.short == short }
      raise tokens.error.new "#{short} is specified ambiguously #{similar.size} times" if similar.size > 1
      if similar.size < 1
        o = Option.new short, nil, 0
        options << o
        if tokens.error == DocoptExit
          o = Option.new short, nil, 0, true
        end
      else
        o = Option.new short, similar[0].long, similar[0].argcount, similar[0].value
        value = nil
        if o.argcount != 0
          if left == ""
            raise tokens.error.new "#{short} requires argument" if [nil, "--"].includes? tokens.current
            value = tokens.move
          else
            value = left
            left = ""
          end
        end
        if tokens.error == DocoptExit
          o.value = value.nil? ? true : value
        end
      end
      parsed << (o.as Pattern)
    end
    parsed
  end

  def self.parse_atom(tokens, options) : Array(Pattern)
    # atom ::= '(' expr ')' | '[' expr ']' | 'options'
    #         | long | shorts | argument | command ;
    token = tokens.current.as String # @TODO maybe nil
    case token
    when "("
      tokens.move
      result = Required.new parse_expr(tokens, options)
      raise "unmatched #{token}" if tokens.move != ")"
      [result.as Pattern]
    when "["
      tokens.move
      result = Optional.new parse_expr(tokens, options)
      raise "unmatched #{token}" if tokens.move != "]"
      [result.as Pattern]
    when "options"
      tokens.move
      [AnyOptions.new([] of Pattern).as Pattern]
    else
      if token.starts_with?("--") && token != "--"
        parse_long(tokens, options)
      elsif token.starts_with?("-") && token != "--" && token != "-"
        parse_shorts(tokens, options)
      elsif token.starts_with?("<") && token.ends_with?(">") || token == token.upcase
        [Argument.new(tokens.move).as Pattern]
      else
        [Command.new(tokens.move).as Pattern]
      end
    end
  end

  def self.parse_seq(tokens, options) : Array(Pattern)
    result = [] of Pattern
    while ![nil, "]", ")", "|"].includes? tokens.current
      atom = parse_atom(tokens, options)
      if tokens.current == "..."
        atom = [(OneOrMore.new atom).as Pattern]
        tokens.move
      end
      result += atom
    end
    result
  end

  def self.parse_expr(tokens, options) : Array(Pattern)
    # expr ::= seq ( '|' seq )* ;
    seq = parse_seq(tokens, options)
    if tokens.current != "|"
      return seq
    end
    result = seq.size > 1 ? [Required.new(seq).as Pattern] : seq
    while tokens.current == "|"
      tokens.move
      seq = parse_seq(tokens, options)
      result += seq.size > 1 ? [Required.new(seq).as Pattern] : seq
    end
    result.size > 1 ? [Either.new(result).as Pattern] : result
  end

  def self.parse_pattern(source, options)
    tokens = Tokens.from_pattern(source)
    result = parse_expr(tokens, options)
    raise "Unexpected ending: #{tokens.join " "}" if !tokens.current.nil?
    Required.new(result)
  end

  def self.parse_argv(tokens, options, options_first = false) : Array(Pattern)
    # Parse command-line argument vector.
    # If options_first:
    #    argv ::= [ long | shorts ]* [ argument ]* [ '--' [ argument ]* ] ;
    # else:
    #    argv ::= [ long | shorts | argument ]* [ '--' [ argument ]* ] ;
    parsed = [] of Pattern
    while !tokens.current.nil?
      tok = tokens.current.as String
      if tok == "--"
        return parsed + tokens.map { |v| Argument.new nil, v }
      elsif tok.starts_with? "--"
        parsed += parse_long(tokens, options)
      elsif tok.starts_with?("-") && tokens.current != "-"
        parsed += parse_shorts(tokens, options)
      elsif options_first
        return parsed + tokens.map { |v| Argument.new nil, v }
      else
        parsed << (Argument.new nil, tokens.move)
      end
    end
    parsed
  end

  def self.extras(help, version, options, doc)
    if help && options.any? { |o| o.is_a?(LeafPattern) && ["-h", "--help"].includes?(o.name) && o.value }
      puts doc.strip # \n
      exit
    end
    if version && options.any? { |o| o.is_a?(LeafPattern) && o.name == "--version" && o.value }
      puts version
      exit
    end
  end

  def self.docopt(doc, argv = nil, help = true, version = nil, options_first = false, exit = true) : Hash(String, (Nil | String | Int32 | Bool | Array(String)))
    argv = ARGV if argv.nil?
    usage_sections = parse_section("usage:", doc)
    if usage_sections.size == 0
      raise DocoptLanguageError.new "\"usage\": (case-insensitive) not found."
    end
    if usage_sections.size > 1
      raise DocoptLanguageError.new "More than one \"usage:\" (case-insensitive)."
    end
    usage = usage_sections[0]
    DocoptExit.usage = usage
    options = parse_defaults(doc)
    pattern = parse_pattern(formal_usage(usage), options)
    argv_pat = parse_argv(Tokens.from_array(argv.map { |x| x }), options, options_first)
    pattern_options = pattern.flat Option
    pattern.flat(AnyOptions).each do |options_shortcut|
      options_shortcut_ = options_shortcut.as BranchPattern
      options_shortcut_.children = (options - pattern_options).uniq.map { |x| x.as Pattern }
    end
    extras(help, version, argv_pat, doc)
    matched, left, collected = pattern.fix.match(argv_pat)
    if matched && left.size == 0
      dic = {} of String => (Nil | String | Int32 | Bool | Array(String))
      (pattern.flat + collected).each do |a|
        if a.is_a? LeafPattern
          name = a.name.as String
          dic[name] = a.value
        end
      end
      # puts dic
      return dic
    end
    raise DocoptExit.new
  rescue ex
    if exit
      msg = ex.message
      if msg.is_a?(String) && msg.size > 0
        puts msg
      end
      puts DocoptExit.usage
      Process.exit
    else
      raise ex
    end
  end
end
