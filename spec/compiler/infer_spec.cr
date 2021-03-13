describe Mare::Compiler::Infer do
  it "complains when calling with an insufficient receiver capability" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :fun ref mutate

    :actor Main
      :new
        Example.mutate
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):6:
        Example.mutate
                ^~~~~~

    - the type Example isn't a subtype of the required capability of 'ref':
      from (example):2:
      :fun ref mutate
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains with an extra hint when using insufficient capability of @" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun ref mutate
      :fun readonly
        @mutate

    :actor Main
      :new
        Example.new.readonly
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):4:
        @mutate
         ^~~~~~

    - the type Example'box isn't a subtype of the required capability of 'ref':
      from (example):2:
      :fun ref mutate
           ^~~

    - this would be possible if the calling function were declared as `:fun ref`:
      from (example):3:
      :fun readonly
       ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when calling on a function with too many arguments" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
      :new
        @example(1, 2, 3)
        @example(1, 2, 3, 4)
        @example(1, 2, 3, 4, 5)
        @example(1, 2, 3, 4, 5, 6)
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):7:
        @example(1, 2, 3, 4, 5, 6)
         ^~~~~~~

    - the call site has too many arguments:
      from (example):7:
        @example(1, 2, 3, 4, 5, 6)
         ^~~~~~~

    - the function allows at most 5 arguments:
      from (example):2:
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when calling on a function with too few arguments" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
      :new
        @example(1, 2, 3, 4, 5)
        @example(1, 2, 3, 4)
        @example(1, 2, 3)
        @example(1, 2)
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):7:
        @example(1, 2)
         ^~~~~~~

    - the call site has too few arguments:
      from (example):7:
        @example(1, 2)
         ^~~~~~~

    - the function requires at least 3 arguments:
      from (example):2:
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "allows safe auto-recovery of a property setter call" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner Inner: Inner.new
      :new iso

    :actor Main
      :new
        outer_iso Outer'iso = Outer.new
        inner_iso Inner'iso = Inner.new
        inner_ref Inner'ref = Inner.new

        outer_iso.inner = --inner_iso
        outer_iso.inner = inner_ref
    SOURCE

    expected = <<-MSG
    This function call won't work unless the receiver is ephemeral; it must either be consumed or be allowed to be auto-recovered. Auto-recovery didn't work for these reasons:
    from (example):15:
        outer_iso.inner = inner_ref
                  ^~~~~

    - the argument (when aliased) has a type of Inner, which isn't sendable:
      from (example):15:
        outer_iso.inner = inner_ref
                          ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains on auto-recovery of a property setter whose return is used" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner Inner: Inner.new
      :new iso

    :actor Main
      :new
        outer_trn Outer'trn = Outer.new
        inner_2 = outer_trn.inner = Inner.new
    SOURCE

    expected = <<-MSG
    This function call won't work unless the receiver is ephemeral; it must either be consumed or be allowed to be auto-recovered. Auto-recovery didn't work for these reasons:
    from (example):11:
        inner_2 = outer_trn.inner = Inner.new
                            ^~~~~

    - the return type Inner isn't sendable and the return value is used (the return type wouldn't matter if the calling side entirely ignored the return value:
      from (example):5:
      :prop inner Inner: Inner.new
            ^~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains on auto-recovery for a val method receiver" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner Inner: Inner.new
      :fun val immutable Inner'val: @inner
      :new iso

    :actor Main
      :new
        outer Outer'iso = Outer.new
        inner Inner'val = outer.immutable
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):12:
        inner Inner'val = outer.immutable
                                ^~~~~~~~~

    - the function's receiver capability is `val` but only a `ref` or `box` receiver can be auto-recovered:
      from (example):6:
      :fun val immutable Inner'val: @inner
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers prop setters to return the alias of the assigned value" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new trn:

    :class Outer
      :prop inner Inner'trn: Inner.new

    :actor Main
      :new
        outer = Outer.new
        inner_box Inner'box = outer.inner = Inner.new // okay
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
    SOURCE

    # TODO: Fix position reporting that isn't quite right here:
    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of Inner'trn:
      from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
                  ^~~~~~~~~

    - but the type of the return value was Inner'box:
      from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
                                    ^~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains if some params of an elevated constructor are not sendable" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :new val (a String'ref, b String'val, c String'box)
        None

    :actor Main
      :new
        Example.new(String.new, "", "")
    SOURCE

    expected = <<-MSG
    A constructor with elevated capability must only have sendable parameters:
    from (example):2:
      :new val (a String'ref, b String'val, c String'box)
           ^~~

    - this parameter type (String'ref) is not sendable:
      from (example):2:
      :new val (a String'ref, b String'val, c String'box)
                ^~~~~~~~~~~~

    - this parameter type (String'box) is not sendable:
      from (example):2:
      :new val (a String'ref, b String'val, c String'box)
                                            ^~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains if some params of an asynchronous function are not sendable" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Example
      :be call (a String'ref, b String'val, c String'box)
        None

    :actor Main
      :new
        Example.new.call(String.new, "", "")
    SOURCE

    expected = <<-MSG
    An asynchronous function must only have sendable parameters:
    from (example):2:
      :be call (a String'ref, b String'val, c String'box)
       ^~

    - this parameter type (String'ref) is not sendable:
      from (example):2:
      :be call (a String'ref, b String'val, c String'box)
                ^~~~~~~~~~~~

    - this parameter type (String'box) is not sendable:
      from (example):2:
      :be call (a String'ref, b String'val, c String'box)
                                            ^~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a constant doesn't meet the expected type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
      :const i8 I8: 1
      :const u64 U64: 2
      :const f64 F32: 3.3
      :const str String: "Hello, World!"
      :const array_i8 Array(I8)'val: [1]
      :const array_u64 Array(U64)'val: [2]
      :const array_f32 Array(F32)'val: [3.3]
      :const array_str Array(String)'val: ["Hello", "World"]
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
    SOURCE

    expected = <<-MSG
    The type of a constant may only be String, a numeric type, or an immutable Array of one of these:
    from (example):11:
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
             ^~~~~~~~~~~~~

    - but the type is Array(String):
      from (example):11:
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
                           ^~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to be present in the subtype" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :fun example1 U64
      :fun example2 U64
      :fun example3 U64

    :class Concrete
      :is Trait
      :fun example2 U64: 0

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this function isn't present in the subtype:
      from (example):2:
      :fun example1 U64
           ^~~~~~~~

    - this function isn't present in the subtype:
      from (example):4:
      :fun example3 U64
           ^~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have the same constructor or constant tags" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :new constructor1
      :new constructor2
      :new constructor3
      :const constant1 U64
      :const constant2 U64
      :const constant3 U64
      :fun function1 U64
      :fun function2 U64
      :fun function3 U64

    :class Concrete
      :is Trait
      :new constructor1
      :const constructor2 U64: 0
      :fun constructor3 U64: 0
      :new constant1
      :const constant2 U64: 0
      :fun constant3 U64: 0
      :new function1
      :const function2 U64: 0
      :fun function3 U64: 0

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):13:
      :is Trait
       ^~

    - a non-constructor can't be a subtype of a constructor:
      from (example):15:
      :const constructor2 U64: 0
             ^~~~~~~~~~~~

    - the constructor in the supertype is here:
      from (example):3:
      :new constructor2
           ^~~~~~~~~~~~

    - a non-constructor can't be a subtype of a constructor:
      from (example):16:
      :fun constructor3 U64: 0
           ^~~~~~~~~~~~

    - the constructor in the supertype is here:
      from (example):4:
      :new constructor3
           ^~~~~~~~~~~~

    - a constructor can't be a subtype of a non-constructor:
      from (example):17:
      :new constant1
           ^~~~~~~~~

    - the non-constructor in the supertype is here:
      from (example):5:
      :const constant1 U64
             ^~~~~~~~~

    - a non-constant can't be a subtype of a constant:
      from (example):19:
      :fun constant3 U64: 0
           ^~~~~~~~~

    - the constant in the supertype is here:
      from (example):7:
      :const constant3 U64
             ^~~~~~~~~

    - a constructor can't be a subtype of a non-constructor:
      from (example):20:
      :new function1
           ^~~~~~~~~

    - the non-constructor in the supertype is here:
      from (example):8:
      :fun function1 U64
           ^~~~~~~~~

    - a constant can't be a subtype of a non-constant:
      from (example):21:
      :const function2 U64: 0
             ^~~~~~~~~

    - the non-constant in the supertype is here:
      from (example):9:
      :fun function2 U64
           ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have the same number of params" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Trait
      :fun example1 (a U64, b U64, c U64) None
      :fun example2 (a U64, b U64, c U64) None
      :fun example3 (a U64, b U64, c U64) None

    :primitive Concrete
      :is Trait
      :fun example1 None
      :fun example2 (a U64, b U64) None
      :fun example3 (a U64, b U64, c U64, d U64) None

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this function has too few parameters:
      from (example):8:
      :fun example1 None
           ^~~~~~~~

    - the supertype has 3 parameters:
      from (example):2:
      :fun example1 (a U64, b U64, c U64) None
                    ^~~~~~~~~~~~~~~~~~~~~

    - this function has too few parameters:
      from (example):9:
      :fun example2 (a U64, b U64) None
                    ^~~~~~~~~~~~~~

    - the supertype has 3 parameters:
      from (example):3:
      :fun example2 (a U64, b U64, c U64) None
                    ^~~~~~~~~~~~~~~~~~~~~

    - this function has too many parameters:
      from (example):10:
      :fun example3 (a U64, b U64, c U64, d U64) None
                    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~

    - the supertype has 3 parameters:
      from (example):4:
      :fun example3 (a U64, b U64, c U64) None
                    ^~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-constructor to have a covariant receiver capability" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :new ref example1
      :new ref example2
      :new ref example3

    :class Concrete
      :is Trait
      :new box example1
      :new ref example2
      :new iso example3

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this constructor's receiver capability is box:
      from (example):8:
      :new box example1
           ^~~

    - it is required to be a subtype of ref:
      from (example):2:
      :new ref example1
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have a contravariant receiver capability" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :fun ref example1 U64
      :fun ref example2 U64
      :fun ref example3 U64

    :class Concrete
      :is Trait
      :fun box example1 U64: 0
      :fun ref example2 U64: 0
      :fun iso example3 U64: 0

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this function's receiver capability is iso:
      from (example):10:
      :fun iso example3 U64: 0
           ^~~

    - it is required to be a supertype of ref:
      from (example):4:
      :fun ref example3 U64
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have covariant return and contravariant params" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Trait
      :fun example1 Numeric
      :fun example2 U64
      :fun example3 (a U64, b U64, c U64) None
      :fun example4 (a Numeric, b Numeric, c Numeric) None

    :primitive Concrete
      :is Trait
      :fun example1 U64: 0
      :fun example2 Numeric: U64[0]
      :fun example3 (a Numeric, b U64, c Numeric) None:
      :fun example4 (a U64, b Numeric, c U64) None:

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):8:
      :is Trait
       ^~

    - this function's return type is Numeric:
      from (example):10:
      :fun example2 Numeric: U64[0]
                    ^~~~~~~

    - it is required to be a subtype of U64:
      from (example):3:
      :fun example2 U64
                    ^~~

    - this parameter type is U64:
      from (example):12:
      :fun example4 (a U64, b Numeric, c U64) None:
                     ^~~~~

    - it is required to be a supertype of Numeric:
      from (example):5:
      :fun example4 (a Numeric, b Numeric, c Numeric) None
                     ^~~~~~~~~

    - this parameter type is U64:
      from (example):12:
      :fun example4 (a U64, b Numeric, c U64) None:
                                       ^~~~~

    - it is required to be a supertype of Numeric:
      from (example):5:
      :fun example4 (a Numeric, b Numeric, c Numeric) None
                                           ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "prefers to show an error about assertions over other subtype failures" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Trait
      :fun example None

    :primitive Concrete
      :is Trait

    :actor Main
      :new
        x Trait = Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):5:
      :is Trait
       ^~

    - this function isn't present in the subtype:
      from (example):2:
      :fun example None
           ^~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "allows assigning from a variable with its refined type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x val = "example"
        if (x <: String) (
          y String = x
        )
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "allows assigning from a parameter with its refined type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new: @refine("example")
      :fun refine (x val)
        if (x <: String) (
          y String = x
        )
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "complains when the match type isn't a subtype of the original" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Exampleable
      :fun non example String

    :actor Main
      :new: @refine("example")
      :fun refine (x String)
        if (x <: Exampleable) x.example
    SOURCE

    expected = <<-MSG
    This type check will never match:
    from (example):7:
        if (x <: Exampleable) x.example
            ^~~~~~~~~~~~~~~~

    - the runtime match type, ignoring capabilities, is Exampleable'any:
      from (example):7:
        if (x <: Exampleable) x.example
                 ^~~~~~~~~~~

    - which does not intersect at all with String:
      from (example):6:
      :fun refine (x String)
                     ^~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a check would require runtime knowledge of capabilities" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new (env): @example("example")
      :fun example (x (String'val | String'ref))
        if (x <: String'ref) (
          x << "..."
        )
    SOURCE

    expected = <<-MSG
    This type check could violate capabilities:
    from (example):4:
        if (x <: String'ref) (
            ^~~~~~~~~~~~~~~

    - the runtime match type, ignoring capabilities, is String'any:
      from (example):4:
        if (x <: String'ref) (
                 ^~~~~~~~~~

    - if it successfully matches, the type will be (String | String'ref):
      from (example):3:
      :fun example (x (String'val | String'ref))
                      ^~~~~~~~~~~~~~~~~~~~~~~~~

    - which is not a subtype of String'ref:
      from (example):4:
        if (x <: String'ref) (
                 ^~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  pending "can also refine a type parameter within a choice body" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Sizeable
      :fun size USize

    :class Generic (A)
      :prop _value A
      :new (@_value)
      :fun ref value_size
        if (A <: Sizeable) (@_value.size)

    :actor Main
      :new
        Generic(String).new("example").value_size
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "tests and conveys transitively reached subtypes to the reach pass" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Exampleable
      :fun non example String

    :primitive Example
      :fun non example String: "Hello, World!"

    :actor Main
      :fun maybe_call_example (e non)
        if (e <: Exampleable) e.example
      :new
        @maybe_call_example(Example)
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    any = ctx.namespace[source]["Any"].as(Mare::Program::Type::Link)
    trait = ctx.namespace[source]["Exampleable"].as(Mare::Program::Type::Link)
    sub = ctx.namespace[source]["Example"].as(Mare::Program::Type::Link)

    any_rt = ctx.infer[any].no_args
    trait_rt = ctx.infer[trait].no_args
    sub_rt = ctx.infer[sub].no_args

    mce_t, mce_f, mce_infer =
      ctx.infer.test_simple!(ctx, source, "Main", "maybe_call_example")
    e_param = mce_f.params.not_nil!.terms.first.not_nil!
    mce_infer.resolved(ctx, e_param).single!.should eq any_rt

    any_subtypes = ctx.infer[any_rt].each_known_complete_subtype(ctx).to_a
    trait_subtypes = ctx.infer[trait_rt].each_known_complete_subtype(ctx).to_a
    sub_subtypes = ctx.infer[sub_rt].each_known_complete_subtype(ctx).to_a

    any_subtypes.should contain(sub_rt)
    any_subtypes.should contain(trait_rt)
    trait_subtypes.should contain(sub_rt)
  end

  it "resolves all matching concrete reifications of abstract functions" do
    source = Mare::Source.new_example <<-SOURCE
    :class Person
      :fun greeting
        "Hello, World"

    :trait Greeter
      :fun greeting (String | None)

    :class World
      :fun meet! (greeter Greeter)
        greeter.greeting.as!(String)

    :actor Main
      :new (env)
        try env.out.print(World.new.meet!(Person.new))
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    t = ctx.namespace[source]["Person"].as(Mare::Program::Type::Link)
    rt = ctx.infer[t].no_args
    f = rt.defn(ctx).find_func!("greeting")
    f_link = f.make_link(rt.link)
    rfs = ctx.infer[f_link].each_reified_func(rt).to_a

    # Thanks to Infer#reach_additional_subtype_relationships, we expect that
    # both the box and ref reifications of this concrete function have been
    # reached, because ref is reached via the abstract Greeter'ref.greeting
    # (and box is reached always as part of normal type checking).
    rfs.map(&.receiver.cap_only.show_type).sort.should eq ["box", "ref"]
  end

  it "handles type-parameter-recursive type aliases" do
    source = Mare::Source.new_example <<-SOURCE
    :alias MyData (A Array'read): (String | U64 | A(MyData(A)))

    :actor Main
      :new (env)
        data MyData(Array'val) = ["Hello", "World", 99, ["Wow", [1, 2, 3]]]
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    t, f, infer = ctx.infer.test_simple!(ctx, source, "Main", "new")
    assign = f.body.not_nil!.terms.first.not_nil!.as(Mare::AST::Relate)
    l_type = assign.lhs.as(Mare::AST::Group).terms.last
    array1 = assign.rhs.as(Mare::AST::Group)
    array2 = array1.terms[3].as(Mare::AST::Group)
    array3 = array2.terms[1].as(Mare::AST::Group)

    expected_left_type = "(String | U64 | Array(MyData(Array'val))'val)"
    expected_right_type = "Array(MyData(Array'val))'val"

    infer.resolved(ctx, assign).show_type.should eq expected_left_type
    infer.resolved(ctx, l_type).show_type.should eq expected_left_type
    infer.resolved(ctx, array1).show_type.should eq expected_right_type
    infer.resolved(ctx, array2).show_type.should eq expected_right_type
    infer.resolved(ctx, array3).show_type.should eq expected_right_type
  end

  it "complains when a type-parameter is directly recursive" do
    source = Mare::Source.new_example <<-SOURCE
    :alias AdInfinitum: (String | U64 | AdInfinitum)

    :actor Main
      :new (env)
        data AdInfinitum = "Uh oh"
    SOURCE

    expected = <<-MSG
    This type alias is directly recursive, which is not supported:
    from (example):1:
    :alias AdInfinitum: (String | U64 | AdInfinitum)
           ^~~~~~~~~~~

    - only recursion via type arguments in this expression is supported:
      from (example):1:
    :alias AdInfinitum: (String | U64 | AdInfinitum)
                        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  pending "complains when the yield block result doesn't match the expected type"
  pending "enforces yield properties as part of trait subtyping"
end
