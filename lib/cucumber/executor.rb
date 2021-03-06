require 'cucumber/core_ext/proc'

module Cucumber
  class Executor
    attr_reader :failed
    attr_accessor :formatter
    
    def line=(line)
      @line = line
    end

    def initialize(step_mother)
      @world_proc = lambda do 
        Object.new
      end
      @before_scenario_procs = []
      @after_scenario_procs = []
      @after_step_procs = []
      @step_mother = step_mother
    end
    
    def register_world_proc(&proc)
      @world_proc = proc
    end

    def register_before_scenario_proc(&proc)
      proc.extend(CoreExt::CallIn)
      @before_scenario_procs << proc
    end

    def register_after_scenario_proc(&proc)
      proc.extend(CoreExt::CallIn)
      @after_scenario_procs << proc
    end

    def register_after_step_proc(&proc)
      proc.extend(CoreExt::CallIn)
      @after_step_procs << proc
    end

    def visit_features(features)
      raise "Line number can only be specified when there is 1 feature. There were #{features.length}." if @line && features.length != 1
      formatter.visit_features(features) if formatter.respond_to?(:visit_features)
      features.accept(self)
      formatter.dump
    end

    def visit_feature(feature)
      formatter.visit_feature(feature) if formatter.respond_to?(:visit_feature)
      feature.accept(self)
    end

    def visit_header(header)
      formatter.header_executing(header) if formatter.respond_to?(:header_executing)
    end

    def visit_row_scenario(scenario)
      visit_scenario(scenario)
    end

    def visit_regular_scenario(scenario)
      visit_scenario(scenario)
    end

    def visit_scenario(scenario)
      if accept?(scenario)
        @error = nil
        @pending = nil

        @world = @world_proc.call
        @world.extend(Spec::Matchers) if defined?(Spec::Matchers)
        define_step_call_methods(@world)

        formatter.scenario_executing(scenario) if formatter.respond_to?(:scenario_executing)
        @before_scenario_procs.each{|p| p.call_in(@world, *[])}
        scenario.accept(self)
        @after_scenario_procs.each{|p| p.call_in(@world, *[])}
        formatter.scenario_executed(scenario) if formatter.respond_to?(:scenario_executed)
      end
    end
    
    def accept?(scenario)
      @line.nil? || scenario.at_line?(@line)
    end

    def visit_row_step(step)
      visit_step(step)
    end

    def visit_regular_step(step)
      visit_step(step)
    end

    def visit_step(step)
      unless @pending || @error
        begin
          regexp, args, proc = step.regexp_args_proc(@step_mother)
          formatter.step_executing(step, regexp, args) if formatter.respond_to?(:step_executing)
          step.execute_in(@world, regexp, args, proc)
          @after_step_procs.each{|p| p.call_in(@world, *[])}
          formatter.step_passed(step, regexp, args)
        rescue Pending
          record_pending_step(step, regexp, args)
        rescue => e
          @failed = true
          @error = step.error = e
          formatter.step_failed(step, regexp, args)
        end
      else
        begin
          regexp, args, proc = step.regexp_args_proc(@step_mother)
          step.execute_in(@world, regexp, args, proc)
          formatter.step_skipped(step, regexp, args)
        rescue Pending
          record_pending_step(step, regexp, args)
        rescue Exception
          formatter.step_skipped(step, regexp, args)
        end
      end
    end
    
    def record_pending_step(step, regexp, args)
      @pending = true
      formatter.step_pending(step, regexp, args)
    end

    def define_step_call_methods(world)
      world.instance_variable_set('@__executor', self)
      world.instance_eval do
        class << self
          def run_step(name)
            _, args, proc = @__executor.instance_variable_get(:@step_mother).regexp_args_proc(name)
            proc.call_in(self, *args)
          end

          %w{given when then and but}.each do |keyword|
            alias_method Cucumber.language[keyword], :run_step
          end
        end
      end
    end
  end
end