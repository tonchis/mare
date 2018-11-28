require "pegmatite"

module Mare
  module AST
    alias A = Symbol | String | UInt64 | Float64 | Array(A)
    
    abstract class Node
      getter pos
      
      def with_pos(source : Source, token : Pegmatite::Token)
        @pos = SourcePos.new(source, token[1], token[2])
        self
      end
    end
    
    class Document < Node
      property list
      def initialize(@list = [] of Declare)
      end
      def name; :doc end
      def to_a: Array(A)
        res = [name] of A
        list.each { |x| res << x.to_a }
        res
      end
    end
    
    class Declare < Node
      property head
      property body
      def initialize(@head = [] of Term, @body = [] of Term)
      end
      def name; :declare end
      def to_a: Array(A)
        [name, head.map(&.to_a), body.map(&.to_a)] of A
      end
      
      def keyword
        head.first.as(Identifier).value
      end
    end
    
    alias Term = Identifier \
      | LiteralString | LiteralInteger | LiteralFloat \
      | Operator | Prefix | Relate | Group
    
    class Identifier < Node
      property value
      def initialize(@value : String)
      end
      def name; :ident end
      def to_a: Array(A); [name, value] of A end
    end
    
    class LiteralString < Node
      property value
      def initialize(@value : String)
      end
      def name; :string end
      def to_a: Array(A); [name, value] of A end
    end
    
    class LiteralInteger < Node
      property value
      def initialize(@value : UInt64)
      end
      def name; :integer end
      def to_a: Array(A); [name, value] of A end
    end
    
    class LiteralFloat < Node
      property value
      def initialize(@value : Float64)
      end
      def name; :float end
      def to_a: Array(A); [name, value] of A end
    end
    
    class Operator < Node
      property value
      def initialize(@value : String)
      end
      def name; :op end
      def to_a: Array(A); [name, value] of A end
    end
    
    class Prefix < Node
      property op
      property term
      def initialize(@op : Operator, @term : Term)
      end
      def name; :prefix end
      def to_a; [name, op.to_a, term.to_a] of A end
    end
    
    class Qualify < Node
      property term
      property group
      def initialize(@term : Term, @group : Group)
      end
      def name; :qualify end
      def to_a; [name, term.to_a, group.to_a] of A end
    end
    
    class Group < Node
      property style
      property terms
      def initialize(@style : String, @terms = [] of Term)
      end
      def name; :group end
      def to_a: Array(A)
        res = [name] of A
        res << style
        terms.each { |x| res << x.to_a }
        res
      end
    end
    
    class Relate < Node
      property terms
      def initialize(@terms = [] of Term)
      end
      def name; :relate end
      def to_a: Array(A)
        res = [name] of A
        terms.each { |x| res << x.to_a }
        res
      end
    end
  end
end
