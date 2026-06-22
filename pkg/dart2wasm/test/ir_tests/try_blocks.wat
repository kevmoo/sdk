(module $module0
  (type $#Top <...>)
  (type $Array<WasmI16> <...>)
  (type $Array<WasmI32> <...>)
  (type $JSExternWrapper <...>)
  (type $JavaScriptStack <...>)
  (global $"WasmArray<WasmI16>[765]" (ref $Array<WasmI16>) <...>)
  (global $"WasmArray<WasmI32>[231]" (ref $Array<WasmI32>) <...>)
  (global $"WasmArray<WasmI32>[765]" (ref $Array<WasmI32>) <...>)
  (global $"\"Caught Error\"" (ref $JSExternWrapper) <...>)
  (global $"\"Caught JSAny\"" (ref $JSExternWrapper) <...>)
  (global $"\"Caught Object\"" (ref $JSExternWrapper) <...>)
  (func $boxJsException (param $var0 externref) (result (ref $#Top)) <...>)
  (func $f  <...>)
  (func $jsExceptionStackTrace (param $var0 externref) (result (ref $JavaScriptStack)) <...>)
  (func $print (param $var0 (ref $#Top)) <...>)
  (@binaryen.inline 0)
  (func $tryBlocks1
    (local $var0 i32)
    (local $var1 (ref null $#Top))
    (local $var2 (ref null $#Top))
    (local $var3 exnref)
    (local $var4 externref)
    block $label0
      block $label1
        block $label2 (result externref) (result (ref exn))
          block $label3 (result (ref $#Top)) (result (ref $#Top)) (result (ref exn))
            try_table
              call $f
              br $label0
            end
            unreachable
          end
          local.set $var3
          local.set $var2
          local.tee $var1
          struct.get $#Top $field0
          local.tee $var0
          i32.const 63
          i32.eq
          if (result i32)
            i32.const 0
          else
            block $label4 (result i32)
              i32.const -1
              global.get $"WasmArray<WasmI32>[231]"
              i32.const 63
              array.get $Array<WasmI32>
              local.get $var0
              i32.add
              local.tee $var0
              i32.const 765
              i32.ge_u
              br_if $label4
              drop
              global.get $"WasmArray<WasmI32>[765]"
              local.get $var0
              array.get $Array<WasmI32>
              i32.const 63
              i32.eq
              if
                global.get $"WasmArray<WasmI16>[765]"
                local.get $var0
                array.get_u $Array<WasmI16>
                br $label4
              end
              i32.const -1
            end $label4
          end
          i32.const -1
          i32.ne
          br_if $label1
          local.get $var3
          ref.as_non_null
          throw_ref
        end
        drop
        local.tee $var4
        call $boxJsException
        drop
        local.get $var4
        call $jsExceptionStackTrace
        drop
      end $label1
      global.get $"\"Caught JSAny\""
      call $print
    end $label0
  )
  (@binaryen.inline 0)
  (func $tryBlocks2
    (local $var0 externref)
    block $label0
      block $label1
        block $label2 (result externref) (result (ref exn))
          block $label3 (result (ref $#Top)) (result (ref $#Top)) (result (ref exn))
            try_table
              call $f
              br $label0
            end
            unreachable
          end
          drop
          drop
          drop
          br $label1
        end
        drop
        local.tee $var0
        call $boxJsException
        drop
        local.get $var0
        call $jsExceptionStackTrace
        drop
      end $label1
      global.get $"\"Caught Object\""
      call $print
    end $label0
  )
  (@binaryen.inline 0)
  (func $tryBlocks3
    (local $var0 i32)
    (local $var1 (ref null $#Top))
    (local $var2 (ref null $#Top))
    (local $var3 exnref)
    block $label0
      block $label1 (result i32)
        block $label2
          block $label3 (result (ref $#Top)) (result (ref $#Top)) (result (ref exn))
            try_table
              call $f
              br $label0
            end
            unreachable
          end
          local.set $var3
          local.set $var2
          local.tee $var1
          struct.get $#Top $field0
          local.tee $var0
          i32.const 56
          i32.le_u
          if
            local.get $var0
            i32.const 33
            i32.le_u
            if
              i32.const 1
              local.get $var0
              i32.const 33
              i32.eq
              br_if $label1
              drop
              br $label2
            end
            i32.const 1
            local.get $var0
            i32.const 45
            i32.ge_u
            br_if $label1
            drop
            br $label2
          end
          local.get $var0
          i32.const 93
          i32.le_u
          if
            i32.const 1
            local.get $var0
            i32.const 93
            i32.eq
            br_if $label1
            drop
            br $label2
          end
          i32.const 1
          local.get $var0
          i32.const 103
          i32.eq
          br_if $label1
          drop
        end $label2
        i32.const 0
      end $label1
      i32.eqz
      if
        local.get $var3
        ref.as_non_null
        throw_ref
      end
      global.get $"\"Caught Error\""
      call $print
    end $label0
  )
)