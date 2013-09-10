#
# The *platin* toolkit
#
# Bridge to absint's "aiT" WCET analyzer
#

require 'platin'

module PML

  # option extensions for aiT
  class OptionParser
    def apx_file(mandatory=true)
      self.on("-a", "--apx FILE", "APX file for a3") { |f| options.apx_file = f }
      self.add_check { |options| die_usage "Option --apx is mandatory" unless options.apx_file } if mandatory
    end
    def ais_file(mandatory=true)
      self.on("--ais FILE", "Path to AIS file") { |f| options.ais_file = f }
      self.add_check { |options| die_usage "Option --ais is mandatory" unless options.ais_file } if mandatory
    end
    def ait_report_prefix(mandatory=true)
      self.on("--ait-report-prefix PREFIX", "Path prefix for aiT's report and XML results") {
        |f| options.ait_report_prefix = f
      }
      self.add_check { |options| die_usage "Option --ait-report-prefix is mandatory" unless options.ait_report_prefix } if mandatory
    end
  end

  # core extensions for aiT
  class ValueRange
    def to_ais
      if s = self.symbol
        dquote(s)
      else
        self.class.range_to_ais(range)
      end
    end
    def ValueRange.range_to_ais(range)
      sprintf("0x%08x .. 0x%08x",range.min,range.max)
    end
  end
  class SymbolicExpression
    def to_ais
      raise Exception.new("#{self.class}#to_ais: no translation available")
    end
  end
  class SEInt
    def to_ais ; self.to_s ; end
  end
  class SEVar
    def to_ais ; "reg #{self}" ; end
  end
  class SEBinary
    def to_ais
      left,right = self.a, self.b
      if SEBinary.commutative?(op) && left.constant? && ! right.constant?
        left, right = right, left
      end
      lexpr, rexpr = [left,right].map { |v| v.to_ais }
      # simplify (x * -1) to (-x)
      if right.constant? && right.constant == -1 && op == '*'
        return "-(#{lexpr})"
      end
      # simplify (a + -b) to (a - b)
      if right.constant? && right.constant < 0 && op == '+'
        return "#{lexpr} - #{-right}"
      end
      # translation of all other ops
      case op
      when '+'    then "(#{lexpr} + #{rexpr})"
      when '*'    then "(#{lexpr} * #{rexpr})"
      when '/u'   then "(#{lexpr} / #{rexpr})"
      when 'umax' then "max(#{lexpr},#{rexpr})"
      when 'umin' then "min(#{lexpr},#{rexpr})"
      # FIXME: how do we deal with signed variables?
      when 'smax' then "max(#{lexpr},#{rexpr})"
      when 'smin' then "min(#{lexpr},#{rexpr})"
      when '/s'   then "(#{lexpr} / #{rexpr})"
      else        raise Exception.new("SymbolicExpression#eval: unknown binary operator #{@op}")
      end
    end
  end

  class AISUnsupportedProgramPoint < Exception
    def initialize(pp, msg = "information references program point not supported by AIS exporter")
      super("#{msg} (#{pp} :: #{pp.class})")
      @pp = pp
    end
  end

  #
  # Extend program points with #ais_ref
  #

  class Function
    def ais_ref
      if self.label
        dquote(self.label)
      elsif self.address
        "0x#{address.to_s(16)}"
      else
        raise AISUnsupportedProgramPoint.new(self, "neither address nor label available (forgot 'platin extract-symbols'?)")
      end
    end
  end

  class Block
    def ais_ref
      if instructions.empty?
        raise AISUnsupportedProgramPoint.new(self, "impossible to reference an empty block")
      end
      if label
        dquote(label)
      elsif address
        "0x#{address.to_s(16)}"
      else
        raise AISUnsupportedProgramPoint.new(self, "neither address nor label available (forgot 'platin extract-symbols'?)")
      end
    end
  end

  class Instruction
    def ais_ref(opts = {})
      if address && block.label
        "#{block.ais_ref} + #{self.address - block.address} bytes"
      elsif opts[:branch_index]
        "#{block.ais_ref} + #{opts[:branch_index]} branches"
      elsif address
        "0x#{address.to_s(16)}"
      else
        raise AISUnsupportedProgramPoint.new(self, "neither address nor symbolic offset available (forgot 'platin extract-symbols'?)")
        # FIXME: we first have to check whether our idea of instruction counting and aiT's match
        # "#{block.ais_ref} + #{self.index} instructions"
      end
    end
  end

  class Loop
    # no automatic translation for loops
    def ais_ref
      raise AISUnsupportedProgramPoint.new(self)
    end
  end
  class Edge
    def ais_ref
      raise AISUnsupportedProgramPoint.new(self)
    end
  end

  class AISExporter

    attr_reader :stats_generated_facts,  :stats_skipped_flowfacts
    attr_reader :outfile, :options

    def initialize(pml,ais_file,options)
      @pml = pml
      @outfile = ais_file
      @options = options
      @entry = @pml.machine_functions.by_label(@options.analysis_entry)
      @extracted_arguments = {}
      @stats_generated_facts, @stats_skipped_flowfacts = 0, 0
    end

    # Generate a global AIS header
    def gen_header
      # TODO get compiler type depending on YAML arch type
      @outfile.puts '# configure compiler'
      @outfile.puts 'compiler "patmos-llvm";'
      @outfile.puts ''

      export_machine_description

      if @options.ais_header_file
        @outfile.puts(File.read(@options.ais_header_file))
      end
      @outfile.puts
    end

    def export_machine_description
      @pml.arch.config.caches.each { |cache|
        case cache.name
        when 'method-cache'
          # not yet supported
        when 'data-cache'
          gen_fact("cache data size=#{cache.size}, associativity=#{cache.associativity}, line-size=#{cache.line_size},"+
                   "policy=#{cache.policy.upcase}, may=chaos", "PML machine configuration")
        when 'instruction-cache'
          gen_fact("cache code size=#{cache.size}, associativity=#{cache.associativity}, line-size=#{cache.line_size},"+
                   "policy=#{cache.policy.upcase}, may=chaos", "PML machine configuration")
        when 'stack-cache'
          # not directly supported (additional cost via platin)
        end
      }
      @pml.arch.config.memory_areas.each { |area|
        kw = if area.type == 'code' then 'code' else 'data' end
        tt_read_beat = area.memory.read_latency + area.memory.read_transfer_time
        tt_write_beat = area.memory.write_latency + area.memory.write_transfer_time
        if area.cache
          tt_read_cache_line = area.memory.read_latency +
            area.memory.read_transfer_time * area.memory.blocks_per_line(area.cache.block_size)
          properties = [ "#{kw} read transfer-time = [#{tt_read_beat},#{tt_read_cache_line}]" ]
        else
          properties = [ "#{kw} read transfer-time = [#{tt_read_beat},#{tt_read_beat}]" ]
        end
        if area.cache
          if area.cache.name == 'method-cache'
            properties.push("#{kw} locked")
          else
            properties.push("#{kw} cached")
          end
        elsif area.type == 'scratchpad'
          properties.push("#{kw} locked")
        end
        if area.type != 'code'
          properties.push("#{kw} write time = #{tt_write_beat}")
        end
        gen_fact("area #{area.address_range.to_ais} access #{properties.join(", ")}",
                 "PML machine configuration")
      }
    end

    def gen_fact(ais_instr, descr, derived_from=nil)
      @stats_generated_facts += 1
      @outfile.puts(ais_instr+";" +" # "+descr)
      debug(@options,:ait) {
        s = " derived from #{derived_from}" if derived_from
        "Wrote AIS instruction: #{ais_instr}#{s}"
      }
      true
    end


    # Export jumptables for a function
    def export_jumptables(func)
      func.blocks.each do |mbb|
        branches = 0
        mbb.instructions.each do |ins|
          branches += 1 if ins.branch_type && ins.branch_type != "none"
          if ins.branch_type == 'indirect'
            successors = ins.branch_targets ? ins.branch_targets : mbb.successors
            targets = successors.uniq.map { |succ|
              succ.ais_ref
            }.join(", ")
            gen_fact("instruction #{ins.ais_ref(:branch_index => branches)} branches to #{targets}","jumptable (source: llvm)",ins)
          end
        end
      end
    end

    # export indirect calls
    def export_calltargets(ff, scope, callsite, targets)
      assert("Bad calltarget flowfact: #{ff.inspect}") { scope && scope.context.empty? }

      # no support for context-sensitive call targets
      unless callsite.context.empty?
        warn("aiT: no support for callcontext-sensitive callsites")
        return false
      end

      called = targets.map { |f| f.ais_ref }.join(", ")
      gen_fact("instruction #{callsite.ais_ref} calls #{called}",
               "global indirect call targets (source: #{ff.origin})",ff)
    end

    # export loop bounds
    def export_loopbounds(scope, bounds_and_ffs)

      # context-sensitive facts not yet supported
      unless scope.context.empty?
        warn("aiT: no support for callcontext-sensitive loop bounds")
        return false
      end
      loopblock = scope.programpoint.loopheader

      origins = Set.new
      ais_bounds = bounds_and_ffs.map { |bound,ff|
        # (1) collect registers needed (and safe)
        # (2) generate symbolic expression
        origins.add(ff.origin)
        bound.referenced_vars.each { |v|
          user_reg = @extracted_arguments[ [loopblock.function,v] ]
          unless user_reg
            user_reg = "@arg_#{v}"
            @extracted_arguments[ [loopblock.function,v] ] = user_reg
            gen_fact("instruction #{loopblock.function.ais_ref} is entered with #{user_reg} = trace(reg #{v})",
                     "extracted argument for symbolic loop bound")
          end
        }
        bound.to_ais
      }
      bound = ais_bounds.length == 1 ? ais_bounds.first : "min(#{ais_bounds.join(",")})"

      # As we export loop header bounds, we should say the loop header is 'at the end'
      # of the loop (confirmed by absint (Gernot))
      loopname = dquote(loopblock.label)
      gen_fact("loop #{loopname} max #{bound} end",
               "global loop header bound (source: #{origins.to_a.join(", ")})")
    end

    # export global infeasibles
    def export_infeasible(ff, scope, pp)

      # context-sensitive facts not yet supported
      unless scope.context.empty? && pp.context.empty?
        warn("aiT: no support for context-sensitive scopes / program points: #{ff}")
        return false
      end

      # no support for empty basic blocks (typically at -O0)
      if pp.programpoint.block.instructions.empty?
        warn("aiT: no support for program points referencing empty blocks: #{ff}")
        return false
      end
      gen_fact("instruction #{pp.block.ais_ref} is never executed",
               "globally infeasible block (source: #{ff.origin})",ff)
    end

    def export_linear_constraint(ff)

      terms_lhs, terms_rhs = [],[]
      terms = ff.lhs.dup
      scope = ff.scope

      unless scope.context.empty?
        warn("aiT: no support for context-sensitive scopes: #{ff}")
        return false
      end

      # no support for context-sensitive linear constraints
      unless  terms.all? { |t| t.context.empty? }
        warn("aiT: no support for context-sensitive scopes / program points: #{ff}")
        return false
      end

      # we only export either (a) local flowfacts (b) flowfacts in the scope of the analysis entry
      type = :unsupported
      if ! scope.programpoint.kind_of?(Function)
        warn("aiT: linear constraint not in function scope (unsupported): #{ff}")
        return false
      end
      if scope.programpoint == @entry
        type = :global
      elsif ff.local?
        type = :local
      else
        warn("aiT: no support for interprocededural flow-facts not relative to analysis entry: #{ff}")
        return false
      end

      # no support for edges in aiT
      unless terms.all? { |t| t.programpoint.kind_of?(Block) }
        warn("Constraint not supported by aiT (not a block ref): #{ff}")
        return false
      end

      # no support for empty basic blocks (typically at -O0)
      if terms.any? { |t| t.programpoint.block.instructions.empty? }
        warn("Constraint not supported by aiT (empty basic block): #{ff})")
        return false
      end

      # Positivity constraints => do nothing
      rhs = ff.rhs.to_i
      if rhs >= 0 && terms.all? { |t| t.factor < 0 }
        return true
      end

      scope = scope.function.blocks.first
      terms.push(Term.new(scope,-rhs)) if rhs != 0
      terms.each { |t|
        set = (t.factor < 0) ? terms_rhs : terms_lhs
        set.push("#{t.factor.abs} (#{t.programpoint.block.ais_ref})")
      }
      cmp_op = "<="
      constr = [terms_lhs, terms_rhs].map { |set|
        set.empty? ? "0" : set.join(" + ")
      }.join(cmp_op)
      gen_fact("flow #{constr}",
               "linear constraint on block frequencies (source: #{ff.origin})",
               ff)
    end

    # export set of flow facts (minimum of loop bounds)
    def export_flowfacts(ffs)
      loop_bounds = {}
      ffs.each { |ff|
        if scope_bound = ff.get_loop_bound
          scope,bound = scope_bound
          next if options.ais_disable_export.include?('loop-bounds')
          next if ! bound.constant? && options.ais_disable_export.include?('symbolic-loop-bounds')
          (loop_bounds[scope]||=[]).push([bound,ff])
        else
          supported = export_flowfact(ff)
          @stats_skipped_flowfacts += 1 unless supported
        end
      }
      loop_bounds.each { |scope,bounds_and_ffs|
        export_loopbounds(scope, bounds_and_ffs)
      }
    end

    # export linear-constraint flow facts
    def export_flowfact(ff)
      assert("export_flowfact: loop bounds need to be exported separately") { ff.get_loop_bound.nil? }

      if (! ff.local?) && ff.scope.function != @entry
        warn("aiT: non-local flow fact in scope #{ff.scope} not supported")
        false

      elsif ff.symbolic_bound?
        debug(options, :ait) { "Symbolic Bounds only supported for loop bounds" }
        false

      elsif scope_cs_targets = ff.get_calltargets
        return false if options.ais_disable_export.include?('call-targets')
        export_calltargets(ff,*scope_cs_targets)

      elsif scope_pp = ff.get_block_infeasible
        return false if options.ais_disable_export.include?('infeasible-code')
        export_infeasible(ff,*scope_pp)

      elsif ff.blocks_constraint? || ff.scope.programpoint.kind_of?(Function)
        return false if options.ais_disable_export.include?('flow-constraints')
        export_linear_constraint(ff)

      else
        warn("aiT: unsupported flow fact type: #{ff}")
        false
      end
    end

    # export value facts
    def export_valuefact(vf)
      assert("AisExport#export_valuefact: programpoint is not an instruction (#{vf.programpoint.class})") { vf.programpoint.kind_of?(Instruction) }
      if ! vf.ppref.context.empty?
        warn("AisExport#export_valuefact: cannot export context-sensitive program point")
        return false
      end
      rangelist = vf.values.map { |v| v.to_ais }.join(", ")
      gen_fact("instruction #{vf.programpoint.ais_ref}" +
               " accesses #{rangelist}",
               "Memory address (source: #{vf.origin})", vf)
    end

    # export stack cache instruction annotation
    def export_stack_cache_annotation(type, ins, value)
      assert("cannot annotate stack cache instruction w/o instruction addresses") { ins.address }
      if(type == :fill)
        feature = "stack_cache_fill_count"
      elsif(type == :spill)
        feature = "stack_cache_spill_count"
      else
        die("aiT: unknown stack cache annotation")
      end

      gen_fact("instruction #{ins.ais_ref} features \"#{feature}\" = #{value}", "SC blocks (source: llvm sca)")
    end
  end

  class APXExporter
    attr_reader :outfile
    def initialize(outfile)
      @outfile = outfile
    end

    def export_project(binary, aisfile, report_prefix, analysis_entry)
      # There is probably a better way to do this .. e.g., use a template file.
      report  = report_prefix + ".txt"
      results = report_prefix + ".xml"
      report_analysis= report_prefix + ".#{analysis_entry}.xml"
      xmlns='xmlns="http://www.absint.com/apx"'
      # XXX TODO: use rexml to build
      @outfile.puts <<EOF
<!DOCTYPE APX>
<project #{xmlns} target="patmos" version="13.04i">
<options #{xmlns}>
 <analyses_options #{xmlns}>
   <extract_annotations_from_source_files #{xmlns}>true</extract_annotations_from_source_files>
   <xml_call_graph>true</xml_call_graph>
   <xml_show_per_context_info>true</xml_show_per_context_info>
   <xml_wcet_path>true</xml_wcet_path>
 </analyses_options>
 <general_options #{xmlns}>
  <include_path #{xmlns}>.</include_path>
  </general_options>
</options>
<files #{xmlns}>
 <executables #{xmlns}>#{File.expand_path binary}</executables>
  <ais #{xmlns}>#{File.expand_path aisfile}</ais>
  <xml_results #{xmlns}>#{File.expand_path results}</xml_results>
  <report #{xmlns}>#{File.expand_path report}</report>
</files>
<analyses #{xmlns}>
 <analysis #{xmlns} enabled="true" type="wcet_analysis" id="aiT">
  <analysis_start #{xmlns}>#{analysis_entry}</analysis_start>
  <xml_report>#{File.expand_path report_analysis}</xml_report>
 </analysis>
</analyses>
</project>
EOF
    end
  end

class AitImport
  attr_reader :pml, :options
  def initialize(pml, options)
    @pml, @options = pml, options
    @routines = {}
    @blocks = {}
    @is_loopblock = {}
    @contexts = {}
  end
  def read_result_file(file)
    doc = Document.new(File.read(file))
    cycles = doc.elements["results/result[1]/cycles"].text.to_i
    scope = pml.machine_functions.by_label(options.analysis_entry)
    TimingEntry.new(scope,
                    cycles,
                    nil,
                    'level' => 'machinecode',
                    'origin' => options.timing_output)
  end
  def read_routines(analysis_elem)
    analysis_elem.each_element("decode/routines/routine") do |elem|
      address = Integer(elem.attributes['address'])
      routine = OpenStruct.new
      routine.instruction = pml.machine_functions.instruction_by_address(address)
      die("Could not find instruction at address #{address}") unless routine.instruction
      die("routine #{routine.instruction} is not a basic block") unless routine.instruction.block.instructions.first == routine.instruction
      if elem.attributes['loop']
        routine.loop = routine.instruction.block
        die("loop routine is not a loop header") unless routine.loop.loopheader?
      else
        routine.function = routine.instruction.function
        die("routine is not entry block") unless routine.function.entry_block == routine.instruction.block
      end
      routine.name = elem.attributes['name']
      @routines[elem.attributes['id']] = routine
      elem.each_element("block") { |be|
        @is_loopblock[be.attributes['id']] = true if elem.attributes['loop']
        unless be.attributes['address']
          debug(options,:ait) { "No address for block #{be}" }
          next
        end
        ins = pml.machine_functions.instruction_by_address(Integer(be.attributes['address']))
        @blocks[be.attributes['id']] = ins
      }
    end
    @routine_names = @routines.values.inject({}) { |memo,r| memo[r.name] = r; memo }
  end
  def read_contexts(contexts_element)
    contexts = {}
    contexts_element.each_element("context") { |elem|
      ctx = OpenStruct.new
      ctx.id = elem.attributes['id']
      ctx.routine = @routines[elem.attributes['routine']]
      if elem.text && elem.text != "no-history"
        ctx.context = elem.text.split(/\s*,\s*/).map { |s|
          callsite_addr, target = s.split("->",2)
          site = pml.machine_functions.instruction_by_address(Integer(callsite_addr))
          if target =~ /\A"(.*)"(?:\[(\d+)\/(\d+)(\.\.)?\])?\Z/
            routine = @routine_names[$1]
            if $2
              peel,last = $2.to_i, $3.to_i
              loopoffset = peel - 1
              loopstep = (peel == last && $3) ? 1 : 0
              LoopContextEntry.new(routine.loop, loopstep, loopoffset, site)
            else
              CallContextEntry.new(site)
            end
          else
            die("invalid contex target: #{target}")
          end
        }
      else
        ctx.context = []
      end
      if @contexts[ctx.id] && @contexts[ctx.id] != ctx
        raise Exception.new("Duplicate context with different meaning: #{ctx.id}")
      end
      @contexts[ctx.id] = Context.from_list(ctx.context)
    }
    contexts
  end
  #
  # read memory address ranges identified during value analysis
  #
  def read_value_analysis_results(analysis_task_elem)

    value_analysis_stats = Hash.new(0)

    facts = []
    fact_attrs = { 'level' => 'machinecode', 'origin' => 'aiT' }

    analysis_task_elem.each_element("value_analysis/value_accesses/value_access") { |e|

      ins = pml.machine_functions.instruction_by_address(Integer(e.attributes['address']))

      e.each_element("value_context") { |ce|

        context = @contexts[ce.attributes['context']]

        ce.each_element("value_step") { |se|

          # value_step#index ? value_step#mode?
          # value_area#mod? value_area#rem?

          fact_pp = ContextRef.new(ins, context)
          is_read = se.attributes['type'] == 'read'
          if is_read
            fact_variable = "mem-address-read"
          else
            fact_variable = "mem-address-write"
          end
          fact_width = se.attributes['width'].to_i

          unpredictable = false
          se.each_element("value_area") { |area|
            unpredictable = true if area.attributes['min'] != area.attributes['max']
          }
          debug(options,:ait) { "Access #{ins} in #{context}" } if unpredictable

          values = []
          se.each_element("value_area") { |area|
            min,max,rem,mod  = %w{min max rem mod}.map { |k|
              Integer(area.attributes[k]) if area.attributes[k]
            }
            # XXX: this is an aiT bug (probably because ranges are represented in a signed way)
            if min >= 0xffff_ffff_8000_000
              min,max = [min,max].map { |v| v - 0xffff_ffff_0000_0000 }
            end
            debug(options,:ait) {
              sprintf("- %s 0x%08x..0x%08x (%d bytes), mod=0x%x rem=0x%x\n",
                      se.attributes['type'],min,max,max-min,mod || -1,rem || -1)
            } if unpredictable
            values.push(ValueRange.new(min,max,nil))
          }
          value_analysis_stats[(unpredictable ? 'un' : '') + 'predictable ' + (is_read ? 'reads' : 'writes')] += 1
          fact_values = ValueSet.new(values)
          facts.push(ValueFact.new(fact_pp, fact_variable, fact_width, fact_values, fact_attrs.dup))
        }
      }
    }
    statistics("AIT",value_analysis_stats) if options.stats
    facts
  end

  #
  # read results from WCET analysis
  #
  def read_wcet_analysis_results(wcet_elem, analysis_entry)
    read_contexts(wcet_elem.get_elements("contexts").first)

    @function_count, @function_cost = {} , Hash.new(0)
    edge_freq, edge_cycles, edge_contrib = {}, {}, {}
    ait_ins_cost, ait_edge_cost = Hash.new(0), Hash.new(0)

    wcet_elem.each_element("wcet_path") { |e|
      rentry = e.get_elements("wcet_entry").first.attributes["routine"]
      entry = @routines[rentry]
      next unless  entry.function == analysis_entry

      e.each_element("wcet_routine") { |re|
        # extract function cost
        routine = @routines[re.attributes['routine']]
        if routine.function
          @function_count[routine.function] = re.attributes['count'].to_i
          @function_cost[routine.function] += re.attributes['cumulative_cycles'].to_i
        else
          # loop cost
        end

        # extract edge cost (relative to LLVM terminology)
        re.each_element("wcet_context") { |ctx_elem|
          context = @contexts[ctx_elem.attributes['context']]

          # deal with aiT's special nodes
          start_nodes, loop_nodes, call_nodes, return_nodes = {}, {}, {}, {}

          # Special Case #1: (StartNode -> Node) is ignored
          # => If the target block is a start block, ignore the edge
          ctx_elem.each_element("wcet_start") { |elem|
            start_nodes[elem.attributes['block']] = true
          }

          # Special Case #2: (Node -> CallNode[Loop]) => (Node -> LoopHeaderNode)
          # => If we have an edge from a node to a 'loop call node', we need to replace
          #    it by an edge to the loop header node
          ctx_elem.each_element("wcet_edge_call") { |call_edge|
            if loopblock = @routines[call_edge.attributes['target_routine']].loop
              loop_nodes[call_edge.attributes['source_block']] = loopblock
            else
              call_nodes[call_edge.attributes['source_block']] = true
            end
          }

          # Special case #3: The unsolveable one?
          # In aiT we have edges from nodes within a loop to loop end nodes,
          # and edges from return nodes to nodes just after loop, but end nodes
          # and return nodes are not connected.
          # So in theory we could have the following situation in LLVM:
          #   a[L1] -> c v d v h[L1]
          #   b[L1] -> c v d v h[L1]
          # and in aiT:
          #   a[L1] -> end  ; return[L1] -> c
          #   b[L1] -> end  ; return[L1] -> d
          # and no sane way to determine the execution frequencies of a->c, a->d, b->c, b->d
          # If, however, all loop exit nodes x have a unique successor E(x) outside of the loop,
          # we simply increment the frequency of x->E(x) if we see x->EndOfLoop.
          # As I do not know of a better way to do it, we stuck with this strategy for now.
          ctx_elem.each_element("wcet_edge_return") { |return_edge|
            return_nodes[return_edge.attributes['target_block']] = true
          }

          ctx_elem.each_element("wcet_edge") { |edge|
            next unless edge.attributes['cycles'] || edge.attributes['path_cycles'] || edge.attributes['count']
            source_block_id = edge.attributes['source_block']
            next if start_nodes[source_block_id]
            next if return_nodes[source_block_id]
            source = @blocks[edge.attributes['source_block']]

            target_block_id = edge.attributes['target_block']
            target = @blocks[edge.attributes['target_block']]
            is_intrablock_target = ! target.nil? && target.index > 0 && ! loop_nodes[target_block_id]
            is_intrablock_target = true if call_nodes[target_block_id]
            target_block = if loop_nodes[target_block_id]
                             loop_nodes[target_block_id]
                           else
                             b = @blocks[target_block_id]
                             b ? b.block : nil
                           end
            count = edge.attributes['count'].to_i
            cum_cycles = edge.attributes['cycles'].to_i
            path_cycles = edge.attributes['path_cycles'].to_i

            if count > 0
              computed_path_cycles = (cum_cycles.to_f / count).to_i
              if path_cycles.to_i > 0
                unless path_cycles*count == cum_cycles
                  die("Inconsistent cummulative cycle count for edge #{source}->#{target_block} in context #{context}")
                end
              else
                path_cycles = computed_path_cycles
              end
            end
            next unless path_cycles

            # We need to map the aiT edge to an LLVM edge
            #
            # In addition to the special cases discussed above,
            # there is the problem of duplicated blocks, as we want to compute cycles per execution,
            # not just cummulative cycles.
            #
            # One case is that we are given cycles for an intraprocedural edge b/i -> b/j (j>0), in different
            # contexts. As there might be several aiT nodes for b/i, we need store the maximum cost for
            # the slice (b/i..b/j) in this case. The frequency is ignored here, it is determined by
            # the frequency of the block anyway.
            # The other case is that we have cycles for an edge b/i -> b'/0; again there might be
            # several aiT nodes for b/i. In this case, we accumulate the frequency of (b -> b'),
            # and store the maximum cost for (b-> b').
            #
            # Later on, we add the maximum cost for every slice (b/i..b/j) to all edges
            # b->b' where b' is a live successor at instruction b/i.
            # Moreover, we add the maximum cost for (b/i -> b') to the edge b->b'.

            if source.block == target_block && is_intrablock_target
              ref = ContextRef.new(source, context)
              ait_ins_cost[ref] = [ait_ins_cost[ref],path_cycles].max
            else
              pml_edge = source.block.edge_to(target_block ? target_block : nil)
              if ! target_block && @is_loopblock[target_block_id]
                # in this case, the target is an end-of-loop node, and we need to add the frequency
                # to the unique out-of-loop successor of the source. If it does not exist, we give up
                exit_successor = nil
                source.block.successors.each { |s|
                  if source.block.exitedge_source?(s)
                    die("More than one exit edge from a block within a loop. This makes it" +
                        "impossible (for us) to determine correct edge frequencies") if exit_successor
                    exit_successor = s
                  end
                }
                die("no loop exit successor for #{source}, although there is an edge to end-of-loop node") unless exit_successor
                pml_edge = source.block.edge_to(exit_successor)
              end
              ref = ContextRef.new(pml_edge, context)
              ait_ins_cost[ref] = [ait_ins_cost[ref],path_cycles].max
              if count > 0
                # info "Adding frequency to intraprocedural edge #{pml_edge}: #{count} (#{edge})"
                (edge_freq[pml_edge]||=Hash.new(0))[context] += count
                (edge_contrib[pml_edge]||=Hash.new(0))[context] += count
              end
            end
          }
        }
      }
    }
    ait_ins_cost.each { |cref, path_cycles|
      context = cref.context
      if cref.programpoint.kind_of?(Instruction)
        ins = cref.programpoint
        ins.block.outgoing_edges.each { |pml_edge|
          if ins.live_successor?(pml_edge.target)
            # info "Adding cost to intrablock edge #{pml_edge}: #{path_cycles}"
            (edge_cycles[pml_edge]||=Hash.new(0))[context] += path_cycles
          else
            # info "#{pml_edge.target} is not a live successor at #{ins}"
          end
        }
      else
        pml_edge = cref.programpoint
        assert("read_wcet_analysis_result: expecting Edge type") { pml_edge.kind_of?(Edge) }

        # info "Adding cost to intraprocedural edge #{pml_edge}: #{path_cycles}"
        (edge_cycles[pml_edge]||=Hash.new(0))[context] += path_cycles
      end
    }
    debug(options,:ait) { |&msgs|
      @function_count.each { |f,c|
        msgs.call "- function #{f}: #{@function_cost[f].to_f / c.to_f} * #{c}"
      }
    }
    profile_list = []
    edge_cycles.each { |e,ctxs|
      debug(options,:ait) { "- edge #{e}" }
      ctxs.each { |ctx,cycles|
        ref = ContextRef.new(e, ctx)
        freq = edge_freq[e] ? edge_freq[e][ctx] : 0
        contrib = edge_contrib[e] ? edge_contrib[e][ctx] : 0
        debug(options,:ait) { sprintf(" -- %s: %d * %d\n",ctx.to_s, cycles, freq) }
        profile_list.push(ProfileEntry.new(ref, cycles, freq, contrib))
      }
    }
    profile_list
  end

  def run
    analysis_entry  = pml.machine_functions.by_label(options.analysis_entry, true)
    timing_entry = read_result_file(options.ait_report_prefix + ".xml")

    ait_report_file = options.ait_report_prefix + ".#{options.analysis_entry}" + ".xml"
    analysis_task_elem = Document.new(File.read(ait_report_file)).get_elements("a3/wcet_analysis_task").first
    read_routines(analysis_task_elem)
    debug(options,:ait) { |&msgs|
      @routines.each do |id, r|
        msgs.call("Routine #{id}: #{r}")
      end
    }

    # read value analysis results
    read_contexts(analysis_task_elem.get_elements("value_analysis/contexts").first)
    if options.ait_import_addresses
      read_value_analysis_results(analysis_task_elem).each { |valuefact|
        pml.valuefacts.add(valuefact)
      }
    end

    # read wcet analysis results
    wcet_elem = analysis_task_elem.get_elements("wcet_analysis").first
    if options.import_block_timing
      timing_list = []
      read_wcet_analysis_results(wcet_elem, analysis_entry).each { |pe|
        timing_list.push(pe)
      }
      timing_entry.profile = Profile.new(timing_list)
    end
    statistics("AIT","imported WCET results" => 1) if options.stats
    pml.timing.add(timing_entry)
  end
end

# end module PML
end