# This file contains a monkey patch of Test::Unit::TestCase.

#--
################################################################################
#                      Copyright (C) 2011 Travis Herrick                       #
################################################################################
#                                                                              #
#                                 \v^V,^!v\^/                                  #
#                                 ~%       %~                                  #
#                                 {  _   _  }                                  #
#                                 (  *   -  )                                  #
#                                 |    /    |                                  #
#                                  \   _,  /                                   #
#                                   \__.__/                                    #
#                                                                              #
################################################################################
# This program is free software: you can redistribute it                       #
# and/or modify it under the terms of the GNU General Public License           #
# as published by the Free Software Foundation,                                #
# either version 3 of the License, or (at your option) any later version.      #
#                                                                              #
# Commercial licensing may be available for a fee under a different license.   #
################################################################################
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY;                                                    #
# without even the implied warranty of MERCHANTABILITY                         #
# or FITNESS FOR A PARTICULAR PURPOSE.                                         #
# See the GNU General Public License for more details.                         #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program.  If not, see <http://www.gnu.org/licenses/>.        #
################################################################################
#++

# Monkey patch Test::Unit::TestCase to make it do cool stuff.
Test::Unit::TestCase.class_eval do
  # Since this is in a class_eval, instance methods need to be wrapped up
  # in class_variable_set or ruby will throw warnings.

  # Indicates whether the class has already been initialized.
  # This combined with @@class_name prevents duplicate patching.
  class_variable_set(:@@initialized, nil)

  # Keeps track of the class that has most recently been initialized.
  # This combined with @@initialized prevents duplicate patching.
  class_variable_set(:@@class_name, nil)

  # Initializes the class
  # and exposes private methods and variables of the class that is being tested.
  def initialize(*args)
    # Call initialize on the superclass.
    super

    @obj   = nil
    @class = nil unless defined?(@class)

    @init_object        = nil unless defined?(@init_object)
    @init_object_params = nil unless defined?(@init_object_params)

    @expose_instance_methods = nil unless defined?(@expose_instance_methods)
    @expose_class_methods    = nil unless defined?(@expose_class_methods)
    @expose_variables        = nil unless defined?(@expose_variables)
    @expose_stack            = nil unless defined?(@expose_stack)

    reset_io

    # This block ensures that tests still work if there is not a class that
    # corresponds with the test file/class.
    begin
      # Get the class that is being tested.
      # Assume that the name of the class is found by removing 'Test'
      # from the test class.
      @class ||= Kernel.const_get(self.class.name.gsub(/Test$/, ''))
      @@initialized = ((@class.name == @@class_name) && @@initialized)
      @@class_name = @class.name
    rescue
      @@initialized = true
      @@class_name = ''
    end

    # Only patch if this code has not yet been run.
    if !@@initialized
      set_instance_method_wrappers if @expose_stack

      # Expose private class methods.
      # We will only expose the methods we are responsible for creating.
      # (i.e. subtracting the superclass's private methods)
      expose_private_methods(:class,
        @class.private_methods -
        @class.superclass.private_methods) if @expose_class_methods

      # Expose private instance methods.
      # We will only expose the methods we are responsible for creating.
      # (i.e. subtracting the superclass's private methods)
      expose_private_methods(:instance,
        @class.private_instance_methods -
        @class.superclass.private_instance_methods) if @expose_instance_methods

      # Expose variables.
      # Requires that variables are assigned to in the constructor.
      if @expose_variables
        init_with_defaults if new_object_on_init?
        instance_variable_list = @obj.nil? ? [] : @obj.instance_variables
        expose_variables @class.class_variables + instance_variable_list
      end

      # Indicate that this code has been run.
      @@initialized = true
    end

    # This is potentially called a second time so that the object will
    # include any goodies we have added here.
    init_with_defaults if new_object_on_init?

    reset_trace

    # If initializing the class with @class.new above kills the app,
    # we need to set it back to running, but we want to do this regardless.
    reset_app_state
  end

  # Sets up functionality for all tests.
  #
  # Tracing is set up here so that it is only running during tests.
  #
  # If you want to disable tracing, simply override the setup method
  # without calling super.
  def setup
    if @expose_stack
      set_trace_func proc { |event, file, line, id, binding, class_name|
        if class_name == @class and
            @stack_trace.last != {:class => class_name.name, :method => id}
          @stack_trace  << {
            :class => class_name.name,
            :method => id,
          }
        end
      }
    end
  end

  # Clean up after each test.
  def teardown
    set_trace_func nil if @expose_stack
  end

  ############################################################################
  protected
  ############################################################################

  # Protected methods are intended for use in this class and/or sub-classes.

  ############################################################################
  # @obj and @class-related methods
  ############################################################################

  # Creates a new instance of the class using the arguments that are passed in.
  #
  # This method also resets the states of other variables prior to creation.
  # ==== Input
  # [*args : Array] The parameters that will be used to create a new instance.
  def create(*args)
    reset_io
    reset_trace
    reset_app_state
    @obj = init_new_object(*args)
  end

  # Creates a new object using the specified parameters.
  # ==== Input
  # [*args : Array] The parameters to send to the new method
  #                 when creating the object.
  def init_new_object(*args)
    @obj = send_to_class(:new, *args)
  end

  # Sets the value of the variable that indicates whether a new object
  # should be created and sets the parameters that will be used.
  # ==== Output
  # [params : Array] The parameters to use when creating the object.
  # ==== Notes
  # This method should only be called from a child class's initialize method.
  # Calling it elsewhere could cause unexpected results.
  def init_object(*params)
    @init_object = true

    case params.length
      when 0
        @init_object_params = nil
      when 1
        @init_object_params = params[0]
      else
        @init_object_params = *params
    end
  end

  # Initializes a new object using the default parameters.
  def init_with_defaults
    init_new_object(*@init_object_params)
  end

  # Sends a call to the class.
  # ==== Input
  # [method : Symbol, String] The method to call.
  # [*args : Array] The parameters to send.
  def send_to_class(method, *args)
    return send_to(@class, method.to_sym, *args)
  end

  # Sends a method to the object in the class variable.
  # ==== Input
  # [method : Symbol, String] The name of the method to call.
  # [*args : Array] Parameters to use when calling the method.
  def send_to_object(method, *args)
    create(*args)
    assert_alive
    return send_to(@obj, method.to_sym)
  end

  ############################################################################
  # Enable Functionality - These should only be called in initialize of a child.
  ############################################################################

  # Indicate that class and instance variables should be made available
  # via public methods.
  def expose_all_variables
    @expose_variables = true
  end

  # Indicate that private class methods should be made available
  # via public class methods.
  def expose_class_methods
    @expose_class_methods = true
  end

  # Indicate that private instance methods should be made available
  # via public instance methods.
  def expose_instance_methods
    @expose_instance_methods = true
  end

  # Enables stack tracing so that assertions which rely on knowing
  # which methods were called may be used.
  def expose_stack
    @expose_stack = true
  end

  ############################################################################
  # I/O support methods.
  ############################################################################

  # Returns the output from stdout as a string.
  # ==== Output
  # [String] The output from stdout.
  #
  #          All trailing line feeds are removed.
  def out
    @out.respond_to?(:string) ?  @out.string.gsub(/\n*\z/, '') : ''
  end

  # Returns the output from stderr as a string.
  # ==== Output
  # [String] The output from stderr.
  #
  #          All trailing line feeds are removed.
  def err
    @err.respond_to?(:string) ?  @err.string.gsub(/\n*\z/, '') : ''
  end

  # Return the actual output to stdout and stderr.
  # ==== Output
  # [Array] Two element array of strings.
  #
  #         The first element is from stdout.
  #
  #         The second element is from stderr.
  def real_finis
    return out, err
  end

  # Reset the stdout and stderr stream variables.
  def reset_io
    @out = StringIO.new
    @err = StringIO.new
  end

  # Wrap a block to capture the output to stdout and stderr.
  # ==== Input
  # [&block : Block] The block of code that will have stdout and stderr trapped.
  def wrap_output(&block)
    begin
      $stdout = @out
      $stderr = @err
      yield
    rescue SystemExit
      TestInternals::AppState.state = :dead
    ensure
      $stdout = STDOUT
      $stderr = STDERR
    end
  end

  ############################################################################
  # Support methods.
  ############################################################################

  # Set the application state to alive.
  def reset_app_state
    TestInternals::AppState.state = :alive unless TestInternals::AppState.alive
  end

  # Resets the trace arrays.
  #
  # This is intended for use in cases where code may be called multiple
  # times in a single test.
  def reset_trace
    @stack_trace = []
    @obj.trace = [] if @obj.respond_to?(:trace=)
  end

  # Shows the trace history as it stands, if the object supports it.
  def show_trace
    return unless defined? @obj
    puts @obj.trace.join("\n" + '-' * 80 + "\n") if @obj.respond_to?(:trace)
  end

  ############################################################################
  # Assertions.
  ############################################################################

  # Asserts that a value is equal to true.
  # ==== Input
  # [value : Any] The value to check for equality against true.
  # [message : String : nil] The message to display if the value is not true.
  def assert_true(value, message = nil)
    assert_equal true, value, message
  end

  # Asserts that a value is equal to false.
  # ==== Input
  # [value : Any] The value to check for equality against false.
  # [message : String : nil] The message to display if the value is not false.
  def assert_false(value, message = nil)
    assert_equal false, value, message
  end

  # Asserts that the negation of a value is true.
  # ==== Input
  # [value : Any] The value which will be negated and then asserted.
  # [message : String : nil] The message to display if the assertion fails.
  def assert_not(value, message = nil)
    assert !value, message
  end

  # Assert that an array has a specified number of elements.
  # ==== Input
  # [array : Array] The array that will have it's length checked.
  # [length : Fixnum] The length that the array should be.
  # [message : String : nil] The message to display if the assertion fails.
  def assert_array_count(array, length, message = nil)
    if message.nil?
      message = "#{array} has #{array.length} item(s), " +
        "but was expected to have #{length}."
    end

    assert array.length == length, message
  end

  ############################################################################
  # Assertions - Stack trace.
  ############################################################################

  # Asserts that a method was called on a class.
  # ==== Input
  # [method_name : String] The name of the method to check for.
  # [class_name : String : @class.name] The name of the class
  #                                     on which <tt>method_name</tt>
  #                                     should have been invoked.
  def assert_method(method_name, class_name = @class.name)
    assert method_called?(method_name.to_sym, class_name),
      "#{class_name}.#{method_name} has not been called."
  end

  # Asserts that a method was not called on a class.
  # ==== Input
  # [method_name : String] The name of the method to check for.
  # [class_name : String : @class.name] The name of the class
  #                                     on which <tt>method_name</tt>
  #                                     should not have been invoked.
  def assert_not_method(method_name, class_name = @class.name)
    assert !method_called?(method_name.to_sym, class_name),
      "#{class_name}.#{method_name} should not be called."
  end

  # Asserts that a method was called with the specified parameters.
  # ==== Input
  # [method_name : String] The name of the method to check.
  # [*args : Array] The parameters that were passed in to the method.
  def assert_trace_args(method_name, *args)
    match = false

    list = []

    # Loop through the stack trace to see if the method was called
    # with the specified arguments.
    @obj.trace.each do |trace|
      if trace[:method] == method_name and trace[:args] == args
        match = true
        break
      elsif trace[:method] == method_name
        list << trace[:args]
      end
    end

    assert match,
      "#{method_name} was not called with the following parameters:\n" +
      "#{args.join("\n" + '-' * 80 + "\n")}\n" +
      '*' * 80 + "\n" +
      "#{method_name} was recorded as follows:\n" +
      "#{list.join("\n" + '-' * 80 + "\n")}"
  end

  # Asserts that a method was called with the specified parameters
  # and returned the specified result.
  # ==== Input
  # [method_name : String] The name of the method to check.
  # [result : Any] The expected result of the method call.
  # [*args : Array] The parameters that were passed in to the method.
  def assert_trace_info(method_name, result, *args)
    match = (@obj.trace.index(
      {:methd => method_name, :args => args, :result => result}))

    list = []

    # Only get a list of possible results if a match was not found.
    unless match
      @obj.trace.each do |trace|
        if trace[:method] == method_name
          list << {:args => trace[:args], :result => trace[:result]}
        end
      end
    end

    assert match,
      "#{method_name} was not called with the following parameters:\n" +
      "#{args}\n" +
      "or did not return the following result:\n" +
      "#{result}\n" +
      "#{method_name} was recorded as follows:\n" +
      "#{list.join("\n" + '-' * 80 + "\n")}"
  end

  ############################################################################
  # Assertions - Application state.
  ############################################################################

  # Asserts that the application is still running.
  # ==== Input
  # [message : String : nil] The message to show if the assertion fails.
  def assert_alive(message = nil)
    message = "#{@class} is not running as expected" if message.nil?

    # Hold the state in a local variable so that the state can be reset
    # prior to the assertion.
    alive = TestInternals::AppState.alive

    # Reset the application state so that later tests are not adversely
    # affected if this assertion fails, which otherwise could leave
    # the application in an incorrect state.
    reset_app_state

    assert alive, message
  end

  # Asserts that the application has been stopped.
  # ==== Input
  # [message : String : nil] The message to show if the assertion fails.
  def assert_dead(message = nil)
    message = "#{@class} was not stopped as expected" if message.nil?

    # Hold the state in a local variable so that the state can be reset
    # prior to the assertion.
    dead = TestInternals::AppState.dead

    # Reset the application state so that later tests are not adversely
    # affected if this assertion fails, which otherwise could leave
    # the application in an incorrect state.
    reset_app_state

    assert dead, message
  end

  ############################################################################
  private
  ############################################################################

  # Private methods are intended for use in this class only.
  # They are NOT intended for use in sub-classes.

  ############################################################################
  # @obj and @class-related methods
  ############################################################################

  # Indicates whether a new object instance should (and can)
  # be created during initialization.
  # ==== Output
  # [Boolean] Whether a new object should (and can) be created.
  def new_object_on_init?
    @init_object && @class.respond_to?(:new)
  end

  # Sends a method to the specified object along with parameters.
  # ==== Input
  # [object : Any] The object to send the method to.
  # [method : Symbol, String] The method to call.
  # [*args : Array] The parameters to pass to the method.
  def send_to(object, method, *args)
    result = nil

    if args.length == 0
      wrap_output { result = object.send(method.to_sym) }
    else
      wrap_output { result = object.send(method.to_sym, *args) }
    end

    return result
  end

  ############################################################################
  # Monkey patching methods for the class being tested.
  ############################################################################

  # Monkey patch the class's initializer to enable tracing
  # with parameters and results.
  def set_initializer
    @class.class_eval do
      attr_accessor :trace

      alias :test_case_initialize :initialize
      def initialize(*args)
        @trace = []
        result = test_case_initialize(*args)
        return result
      end
    end
  end

  # Loop through the instance methods, calling set_instance_methods for each.
  def set_instance_method_wrappers
    [
      :public_instance_methods,
      :protected_instance_methods,
      :private_instance_methods,
    ].each do |method_id|

      scope = method_id.to_s.gsub(/_.*/, '')

      set_instance_methods(@class.send(method_id) -
        @class.superclass.send(method_id), scope)
    end

    # If this is not at the end, the loop will attempt to do it's thing
    # with the constructor created in this method, which is not necessary.
    set_initializer
  end

  # Loop through the list of methods that are passed in,
  # creating a wrapper method that enables tracing.
  #
  # Tracing data includes method name, parameters, and result.
  # ==== Input
  # [method_list : Array] A list of methods that will have wrapping functions
  #                       created to enable tracing.
  # [scope : String] The scope of the original function.
  def set_instance_methods(method_list, scope)
    method_list.each do |method_id|
      # Setters and methods that accept blocks do not appear to work.
      next if method_id =~ /=/ or method_id =~ /wrap_output/

      # Build the method.
      new_method = <<-DOC
        alias :test_case_#{method_id} :#{method_id}
        def #{method_id}(*args)
          result = test_case_#{method_id}(*args)
          @trace << {
            :method => '#{method_id}',
            :args => args,
            :result => result
          }
          return result
        end
        #{scope} :#{method_id}
      DOC

      # Add the method to the class.
      @class.class_eval do
        eval(new_method)
      end
    end
  end

  # Expose the private methods that are passed in.  New methods will be created
  # with the old method name followed by '_public_test'.  If the original
  # method contained a '?', it will be removed in the new method.
  # ==== Input
  # [type : Symbol] Indicates whether to handle instance or class methods.
  #
  #                 Only :class and :instance are supported.
  # [methods : Array] An array of the methods to expose.
  def expose_private_methods(type, methods)
    # Get the text that the method should be wrapped in.
    method_wrapper = wrapper(type)

    # Loop through the methods.
    methods.each do |method|
      # Remove ?s.
      new_method = method.to_s.gsub(/\?/, '')

      # This is the new method.
      new_method = <<-DOC
        def #{new_method}_public_test(*args)
          #{method}(*args)
        end
      DOC

      # Add the wrapping text.
      new_method = method_wrapper % [new_method]

      # Add the method to the class.
      @class.class_eval do
        eval(new_method)
      end
    end
  end

  # Expose the variables.
  #
  # New methods will be created (a getter and a setter) for each variable.
  #
  # Regardless of the type of variable, these methods are only available
  # via an instance.
  # ==== Input
  # [variables : Array] An array of variables to expose.
  def expose_variables(variables)
    # Get the text that the methods should be wrapped in.
    var_wrapper = wrapper(:instance)

    # Loop through the variables
    variables.each do |var|
      # Remove any @s.
      new_method = var.to_s.gsub(/@/, '')

      # These are the new getter and setters.
      new_method = <<-DOC
        def #{new_method}_variable_method
          #{var}
        end

        def #{new_method}_variable_method=(value)
          #{var} = value
        end
      DOC

      # Add the wrapping text.
      new_method = var_wrapper % [new_method]

      # Add the methods to the class.
      @class.class_eval do
        eval(new_method)
      end
    end
  end

  # Returns the wrapping text for the specified type of method.
  # ==== Input
  # [type : Symbol] Indicates whether to handle instance or class methods.
  #
  #                 Only :class & :instance are supported.
  # ==== Output
  # [String] The text that the specified type of method should be wrapped in.
  def wrapper(type)
    case type
      when :class then 'class << self;%s;end'
      when :instance then '%s'
    end
  end

  ############################################################################
  # Support methods.
  ############################################################################

  # Indicates whether the specified method has been called on a given class.
  # ==== Input
  # [method_name : String] The name of the method.
  #
  #                        This value may be a string or a symbol.
  # [class_name : String : @class.name] The name of the class that the method
  #                                     should have been invoked from.
  def method_called?(method_name, class_name = @class.name)
    !@stack_trace.index(
      {:method => method_name.to_sym, :class => class_name}).nil?
  end
end
