describe Mare::Compiler::Completeness do
  it "complains when a constructor has an error-able body" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        error!
    SOURCE
    
    expected = <<-MSG
    This constructor may raise an error, but that is not allowed:
    from (example):2:
      :new
       ^~~
    
    - an error may be raised here:
      from (example):3:
        error!
        ^~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :verify)
    end
  end
  
  it "complains when a no-exclamation function has an error-able body" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
    
    :primitive Example
      :fun risky (x U64)
        if (x == 0) (error!)
    SOURCE
    
    expected = <<-MSG
    This function name needs an exclamation point because it may raise an error:
    from (example):5:
      :fun risky (x U64)
           ^~~~~
    
    - it should be named 'risky!' instead:
      from (example):5:
      :fun risky (x U64)
           ^~~~~
    
    - an error may be raised here:
      from (example):6:
        if (x == 0) (error!)
                     ^~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :verify)
    end
  end
  
  it "complains when a try body has no possible errors to catch" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        try (U64[33] * 3)
    SOURCE
    
    expected = <<-MSG
    This try block is unnecessary:
    from (example):3:
        try (U64[33] * 3)
        ^~~
    
    - the body has no possible error cases to catch:
      from (example):3:
        try (U64[33] * 3)
            ^~~~~~~~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :verify)
    end
  end
end
