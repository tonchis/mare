##
# The purpose of the Namespace pass is to determine which type names are visible
# from which source files, and to raise an appropriate error in the event that
# two types visible from the same source file have the same identifier.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the program level.
# This pass produces output state at the source and source library level.
#
class Mare::Compiler::Namespace
  def initialize
    @types_by_library = Hash(Program::Library::Link, Hash(String, Program::Type::Link | Program::TypeAlias::Link)).new
    @types_by_source = Hash(Source, Hash(String, Program::Type::Link | Program::TypeAlias::Link)).new
  end

  def main_type!(ctx); main_type?(ctx).not_nil! end
  def main_type?(ctx): Program::Type::Link?
    root_library_link = ctx.program.libraries.first.make_link
    @types_by_library[root_library_link]["Main"]?.as(Program::Type::Link?)
  end

  def run(ctx)
    # Take note of the library and source file in which each type occurs.
    ctx.program.libraries.each do |library|
      library.types.each do |t|
        add_type_to_library(ctx, t, library)
        add_type_to_source(t, library)
      end
      library.aliases.each do |t|
        add_type_to_library(ctx, t, library)
        add_type_to_source(t, library)
      end
    end

    # Every source file implicitly has access to all prelude types.
    @types_by_source.each do |source, source_types|
      add_prelude_types_to_source(ctx, source, source_types)
    end

    # Every source file implicitly has access to all types in the same library.
    ctx.program.libraries.each do |library|
      @types_by_source.each do |source, source_types|
        next unless source.library == library.source_library
        source_types.merge!(@types_by_library[library.make_link])
      end
    end

    # Every source file has access to all explicitly imported types.
    ctx.program.libraries.flat_map(&.imports).each do |import|
      add_imported_types_to_source(ctx, import)
    end
  end

  # TODO: Can this be less hacky? It feels wrong to alter this state later.
  def add_lambda_type_later(ctx : Context, new_type : Program::Type, library : Program::Library)
    add_type_to_library(ctx, new_type, library)
    add_type_to_source(new_type, library)
  end

  def [](*args)
    result = self[*args]?

    raise "failed to find asserted type in namespace: #{args.last.inspect}" \
      unless result

    result.not_nil!
  end

  # When given an Identifier, try to find the type starting from its source.
  # This is the way to resolve a type identifier in context.
  def []?(ident : AST::Identifier) : (Program::Type::Link | Program::TypeAlias::Link)?
    @types_by_source[ident.pos.source][ident.value]?
  end
  def []?(ctx, ident : AST::Identifier) : (Program::Type | Program::TypeAlias)?
    self[ident]?.try(&.resolve(ctx))
  end

  # When given a String name, try to find the type in the prelude library.
  # This is a way to resolve a builtin type by name without more context.
  def []?(name : String) : (Program::Type::Link | Program::TypeAlias::Link)?
    @types_by_library[Compiler.prelude_library_link]?.try(&.[]?(name))
  end
  def []?(ctx, name : String) : (Program::Type | Program::TypeAlias)?
    self[name]?.try(&.resolve(ctx))
  end

  # When given an String name and Source, try to find the named type.
  # This is not very commonly what you want.
  def in_source(source : Source, name : String)
    @types_by_source[source][name]?
  end

  # TODO: Remove this method?
  # This is only for use in testing.
  def find_func!(ctx, source, type_name, func_name)
    self.in_source(source, type_name).as(Program::Type::Link).resolve(ctx).find_func!(func_name)
  end

  private def add_type_to_library(ctx, new_type, library)
    name = new_type.ident.value

    types = @types_by_library[library.make_link] ||=
      Hash(String, Program::Type::Link | Program::TypeAlias::Link).new

    already_type_link = types[name]?
    if already_type_link
      already_type = already_type_link.resolve(ctx)
      Error.at new_type.ident.pos,
        "This type conflicts with another declared type in the same library", [
          {already_type.ident.pos, "the other type with the same name is here"}
        ]
    end

    types[name] = new_type.make_link(library)
  end

  private def add_type_to_source(new_type, library)
    source = new_type.ident.pos.source
    name = new_type.ident.value

    types = @types_by_source[source] ||=
      Hash(String, Program::Type::Link | Program::TypeAlias::Link).new

    raise "should have been prevented by add_type_to_library" if types[name]?

    types[name] = new_type.make_link(library)
  end

  private def add_prelude_types_to_source(ctx, source, source_types)
    # Skip adding prelude types to source files in the prelude library.
    return if source.library.path == Compiler.prelude_library_path

    @types_by_library[Compiler.prelude_library_link].each do |name, new_type_link|
      new_type = new_type_link.resolve(ctx)
      next if new_type.has_tag?(:private)

      already_type = source_types[name]?.try(&.resolve(ctx))
      if already_type
        Error.at already_type.ident.pos,
          "This type's name conflicts with a mandatory built-in type", [
            {new_type.ident.pos, "the built-in type is defined here"},
          ]
      end

      source_types[name] = new_type_link
    end
  end

  private def add_imported_types_to_source(ctx, import)
    source = import.ident.pos.source
    library = import.resolved
    importable_types = @types_by_library[library.make_link]

    # Determine the list of types to be imported.
    imported_types = [] of Tuple(Source::Pos, Program::Type::Link | Program::TypeAlias::Link)
    if import.names
      import.names.not_nil!.terms.map do |ident|
        raise NotImplementedError.new(ident) unless ident.is_a?(AST::Identifier)

        new_type_link = importable_types[ident.value]?
        Error.at ident, "This type doesn't exist within the imported library" \
          unless new_type_link

        new_type = new_type_link.resolve(ctx)
        Error.at ident, "This type is private and cannot be imported" \
          if new_type.has_tag?(:private)

        imported_types << {ident.pos, new_type_link}
      end
    else
      importable_types.values.each do |new_type_link|
        new_type = new_type_link.resolve(ctx)
        next if new_type.has_tag?(:private)

        imported_types << {import.ident.pos, new_type_link}
      end
    end

    types = @types_by_source[source] ||=
      Hash(String, Program::Type::Link | Program::TypeAlias::Link).new

    # Import those types into the source, raising an error upon any conflict.
    imported_types.each do |import_pos, new_type_link|
      new_type = new_type_link.resolve(ctx)

      already_type_link = types[new_type.ident.value]?
      if already_type_link
        already_type = already_type_link.resolve(ctx)
        Error.at import_pos,
          "A type imported here conflicts with another " \
          "type already in this source file", [
            {new_type.ident.pos, "the imported type is here"},
            {already_type.ident.pos, "the other type with the same name is here"},
          ]
      end

      types[new_type.ident.value] = new_type_link
    end
  end
end
