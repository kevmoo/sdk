(module $module0
  (type $"<context file:///.../async_try_blocks.dart:16:31>" <...>)
  (type $"<context file:///.../async_try_blocks.dart:27:33>" <...>)
  (type $#Top <...>)
  (type $JSExternWrapper <...>)
  (type $JavaScriptStack <...>)
  (type $Object <...>)
  (type $_Future <...>)
  (type $_InterfaceType <...>)
  (type $_TopType <...>)
  (type $_Type <...>)
  (rec
    (type $type0 <...>)
    (type $_AsyncSuspendState <...>)
  )
  (tag $tag0 (param (ref $#Top) (ref $Object)))
  (global $"\"caught \"" (ref $JSExternWrapper) <...>)
  (global $"\"caught js \"" (ref $JSExternWrapper) <...>)
  (global $"\"dart error\"" (ref $JSExternWrapper) <...>)
  (global $"\"finally\"" (ref $JSExternWrapper) <...>)
  (global $"\"try js\"" (ref $JSExternWrapper) <...>)
  (global $"\"try\"" (ref $JSExternWrapper) <...>)
  (global $_InterfaceType (ref $_InterfaceType) <...>)
  (global $_TopType (ref $_TopType) <...>)
  (global $global0 (ref $type0) <...>)
  (global $global2 (ref $type0) <...>)
  (func $"testAsyncTryCatch inner" (param $var0 (ref $_AsyncSuspendState)) (param $var1 (ref null $#Top)) (param $var2 (ref null $#Top)) (param $var3 (ref null $Object)) (result (ref null $#Top))
    (local $context (ref null $"<context file:///.../async_try_blocks.dart:16:31>"))
    (local $targetIndex i32)
    (local $var4 (ref $#Top))
    (local $var5 (ref $Object))
    (local $var6 (ref $Object))
    (local $var7 (ref $#Top))
    (local $var8 (ref null $#Top))
    (local $var9 (ref null $Object))
    (local $var10 externref)
    (local $var11 (ref $Object))
    (local $var12 (ref $#Top))
    (local $var13 (ref null $#Top))
    (local $var14 (ref null $Object))
    (local $var15 externref)
    (local $var16 (ref $Object))
    (local $var17 (ref $#Top))
    (local $var18 (ref null $#Top))
    (local $var19 (ref null $Object))
    (local $var20 externref)
    (local $var21 (ref $Object))
    (local $var22 (ref $#Top))
    (local $var23 (ref null $#Top))
    (local $var24 (ref null $Object))
    (local $var25 externref)
    (local $var26 (ref $Object))
    (local $var27 (ref $#Top))
    (local $var28 (ref null $#Top))
    (local $var29 (ref null $Object))
    (local $var30 externref)
    (local $var31 (ref $Object))
    (local $var32 (ref $#Top))
    (local $var33 externref)
    local.get $var0
    struct.get $_AsyncSuspendState $_targetIndex
    local.set $targetIndex
    block $label0
      block $label1 (result (ref $#Top)) (result (ref $Object))
        block $label2 (result externref)
          try_table
            loop $label3
              block $label4
                block $label5
                  block $label6
                    block $label7
                      block $label8
                        block $label9
                          block $label10
                            local.get $targetIndex
                            br_table $label10 $label9 $label8 $label7 $label6 $label5 $label4
                          end $label10
                          local.get $var0
                          struct.get $_AsyncSuspendState $_context
                          ref.cast null $"<context file:///.../async_try_blocks.dart:16:31>"
                          local.set $context
                          local.get $context
                          i64.const 0
                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                          block $label11
                            block $label12 (result (ref $#Top)) (result (ref $Object))
                              block $label13 (result externref)
                                try_table
                                  block $label14
                                    block $label15 (result (ref $#Top)) (result (ref $Object))
                                      block $label16 (result externref)
                                        try_table
                                          global.get $"\"try\""
                                          call $print
                                          ref.null none
                                          drop
                                          global.get $"\"dart error\""
                                          local.set $var4
                                          call $StackTrace.current
                                          local.set $var5
                                          local.get $context
                                          i64.const 2
                                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                                          local.get $context
                                          local.get $var4
                                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                                          local.get $context
                                          local.get $var5
                                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                                          local.get $var4
                                          local.get $var5
                                          call $Error._throw
                                          unreachable
                                        end
                                        unreachable
                                      end
                                      local.set $var10
                                      local.get $var10
                                      call $boxJsException
                                      local.set $var7
                                      local.get $var10
                                      call $jsExceptionStackTrace
                                      local.set $var6
                                      local.get $var0
                                      struct.get $_AsyncSuspendState $_currentException
                                      local.set $var8
                                      local.get $var0
                                      struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                                      local.set $var9
                                      local.get $var0
                                      local.get $var7
                                      struct.set $_AsyncSuspendState $_currentException
                                      local.get $var0
                                      local.get $var6
                                      struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                                      br $label9
                                    end
                                    local.set $var6
                                    local.set $var7
                                    local.get $var0
                                    struct.get $_AsyncSuspendState $_currentException
                                    local.set $var8
                                    local.get $var0
                                    struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                                    local.set $var9
                                    local.get $var0
                                    local.get $var7
                                    struct.set $_AsyncSuspendState $_currentException
                                    local.get $var0
                                    local.get $var6
                                    struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                                    br $label9
                                  end
                                  br $label11
                                end
                                unreachable
                              end
                              local.set $var15
                              local.get $var15
                              call $boxJsException
                              local.set $var12
                              local.get $var15
                              call $jsExceptionStackTrace
                              local.set $var11
                              local.get $context
                              i64.const 2
                              struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                              local.get $context
                              local.get $var12
                              struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                              local.get $context
                              local.get $var11
                              struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                              local.get $var0
                              struct.get $_AsyncSuspendState $_currentException
                              local.set $var13
                              local.get $var0
                              struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                              local.set $var14
                              local.get $var0
                              local.get $var12
                              struct.set $_AsyncSuspendState $_currentException
                              local.get $var0
                              local.get $var11
                              struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                              br $label6
                            end
                            local.set $var11
                            local.set $var12
                            local.get $context
                            i64.const 2
                            struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                            local.get $context
                            local.get $var12
                            struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                            local.get $context
                            local.get $var11
                            struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                            local.get $var0
                            struct.get $_AsyncSuspendState $_currentException
                            local.set $var13
                            local.get $var0
                            struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                            local.set $var14
                            local.get $var0
                            local.get $var12
                            struct.set $_AsyncSuspendState $_currentException
                            local.get $var0
                            local.get $var11
                            struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                            br $label6
                          end $label11
                        end $label9
                        block $label17
                          block $label18 (result (ref $#Top)) (result (ref $Object))
                            block $label19 (result externref)
                              try_table
                                local.get $context
                                local.get $var0
                                struct.get $_AsyncSuspendState $_currentException
                                ref.as_non_null
                                struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field3
                                local.get $context
                                local.get $var0
                                struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                                struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field4
                                global.get $"\"caught \""
                                local.get $context
                                struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field3
                                call $JSStringImpl._interpolate2
                                call $print
                                ref.null none
                                drop
                                local.get $context
                                struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field3
                                drop
                                local.get $context
                                struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field4
                                drop
                                br $label8
                              end
                              unreachable
                            end
                            local.set $var20
                            local.get $var20
                            call $boxJsException
                            local.set $var17
                            local.get $var20
                            call $jsExceptionStackTrace
                            local.set $var16
                            local.get $context
                            i64.const 2
                            struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                            local.get $context
                            local.get $var17
                            struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                            local.get $context
                            local.get $var16
                            struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                            local.get $var0
                            struct.get $_AsyncSuspendState $_currentException
                            local.set $var18
                            local.get $var0
                            struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                            local.set $var19
                            local.get $var0
                            local.get $var17
                            struct.set $_AsyncSuspendState $_currentException
                            local.get $var0
                            local.get $var16
                            struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                            br $label6
                          end
                          local.set $var16
                          local.set $var17
                          local.get $context
                          i64.const 2
                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                          local.get $context
                          local.get $var17
                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                          local.get $context
                          local.get $var16
                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                          local.get $var0
                          struct.get $_AsyncSuspendState $_currentException
                          local.set $var18
                          local.get $var0
                          struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                          local.set $var19
                          local.get $var0
                          local.get $var17
                          struct.set $_AsyncSuspendState $_currentException
                          local.get $var0
                          local.get $var16
                          struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                          br $label6
                        end
                      end $label8
                      block $label20
                        block $label21 (result (ref $#Top)) (result (ref $Object))
                          block $label22 (result externref)
                            try_table
                              local.get $var0
                              local.get $var18
                              struct.set $_AsyncSuspendState $_currentException
                              local.get $var0
                              local.get $var19
                              struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                              br $label7
                            end
                            unreachable
                          end
                          local.set $var25
                          local.get $var25
                          call $boxJsException
                          local.set $var22
                          local.get $var25
                          call $jsExceptionStackTrace
                          local.set $var21
                          local.get $context
                          i64.const 2
                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                          local.get $context
                          local.get $var22
                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                          local.get $context
                          local.get $var21
                          struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                          local.get $var0
                          struct.get $_AsyncSuspendState $_currentException
                          local.set $var23
                          local.get $var0
                          struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                          local.set $var24
                          local.get $var0
                          local.get $var22
                          struct.set $_AsyncSuspendState $_currentException
                          local.get $var0
                          local.get $var21
                          struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                          br $label6
                        end
                        local.set $var21
                        local.set $var22
                        local.get $context
                        i64.const 2
                        struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                        local.get $context
                        local.get $var22
                        struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                        local.get $context
                        local.get $var21
                        struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                        local.get $var0
                        struct.get $_AsyncSuspendState $_currentException
                        local.set $var23
                        local.get $var0
                        struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                        local.set $var24
                        local.get $var0
                        local.get $var22
                        struct.set $_AsyncSuspendState $_currentException
                        local.get $var0
                        local.get $var21
                        struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                        br $label6
                      end
                    end $label7
                    block $label23
                      block $label24 (result (ref $#Top)) (result (ref $Object))
                        block $label25 (result externref)
                          try_table
                            local.get $context
                            i64.const 0
                            struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                            br $label6
                          end
                          unreachable
                        end
                        local.set $var30
                        local.get $var30
                        call $boxJsException
                        local.set $var27
                        local.get $var30
                        call $jsExceptionStackTrace
                        local.set $var26
                        local.get $context
                        i64.const 2
                        struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                        local.get $context
                        local.get $var27
                        struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                        local.get $context
                        local.get $var26
                        struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                        local.get $var0
                        struct.get $_AsyncSuspendState $_currentException
                        local.set $var28
                        local.get $var0
                        struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                        local.set $var29
                        local.get $var0
                        local.get $var27
                        struct.set $_AsyncSuspendState $_currentException
                        local.get $var0
                        local.get $var26
                        struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                        br $label6
                      end
                      local.set $var26
                      local.set $var27
                      local.get $context
                      i64.const 2
                      struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                      local.get $context
                      local.get $var27
                      struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                      local.get $context
                      local.get $var26
                      struct.set $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                      local.get $var0
                      struct.get $_AsyncSuspendState $_currentException
                      local.set $var28
                      local.get $var0
                      struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                      local.set $var29
                      local.get $var0
                      local.get $var27
                      struct.set $_AsyncSuspendState $_currentException
                      local.get $var0
                      local.get $var26
                      struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                      br $label6
                    end
                  end $label6
                  global.get $"\"finally\""
                  call $print
                  ref.null none
                  drop
                  local.get $context
                  struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                  drop
                  local.get $context
                  struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                  drop
                  local.get $context
                  struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                  drop
                  local.get $context
                  struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                  i32.wrap_i64
                  i32.eqz
                  if
                    br $label5
                  end
                  local.get $context
                  struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                  i32.wrap_i64
                  i32.const 1
                  i32.eq
                  if
                    local.get $var0
                    local.get $var0
                    struct.get $_AsyncSuspendState $_currentReturnValue
                    call $_AsyncSuspendState._complete
                    ref.null none
                    return
                  end
                  local.get $context
                  struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                  i32.wrap_i64
                  i32.const 2
                  i32.eq
                  if
                    local.get $context
                    struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field1
                    ref.as_non_null
                    local.get $context
                    struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field2
                    ref.as_non_null
                    throw $tag0
                  end
                  local.get $context
                  struct.get $"<context file:///.../async_try_blocks.dart:16:31>" $field0
                  i32.wrap_i64
                  i32.const 3
                  i32.sub
                  local.set $targetIndex
                  br $label3
                end $label5
              end $label4
              local.get $var0
              ref.null $#Top
              call $_AsyncSuspendState._complete
              ref.null none
              ref.null $#Top
              return
            end $label3
            br $label0
          end
          unreachable
        end
        local.set $var33
        local.get $var33
        call $boxJsException
        local.set $var32
        local.get $var33
        call $jsExceptionStackTrace
        local.set $var31
        local.get $var0
        local.get $var32
        local.get $var31
        call $_AsyncSuspendState._completeError
        ref.null none
        ref.null $#Top
        return
      end
      local.set $var31
      local.set $var32
      local.get $var0
      local.get $var32
      local.get $var31
      call $_AsyncSuspendState._completeError
      ref.null none
      ref.null $#Top
      return
    end $label0
    unreachable
  )
  (func $"testAsyncTryCatchJs inner" (param $var0 (ref $_AsyncSuspendState)) (param $var1 (ref null $#Top)) (param $var2 (ref null $#Top)) (param $var3 (ref null $Object)) (result (ref null $#Top))
    (local $context (ref null $"<context file:///.../async_try_blocks.dart:27:33>"))
    (local $targetIndex i32)
    (local $var4 (ref $Object))
    (local $var5 (ref $#Top))
    (local $var6 (ref null $#Top))
    (local $var7 (ref null $Object))
    (local $var8 externref)
    (local $var9 (ref $Object))
    (local $var10 (ref $#Top))
    (local $var11 externref)
    local.get $var0
    struct.get $_AsyncSuspendState $_targetIndex
    local.set $targetIndex
    block $label0
      block $label1 (result (ref $#Top)) (result (ref $Object))
        block $label2 (result externref)
          try_table
            loop $label3
              block $label4
                block $label5
                  block $label6
                    block $label7
                      block $label8
                        local.get $targetIndex
                        br_table $label8 $label7 $label6 $label5 $label4
                      end $label8
                      local.get $var0
                      struct.get $_AsyncSuspendState $_context
                      ref.cast null $"<context file:///.../async_try_blocks.dart:27:33>"
                      local.set $context
                      block $label9
                        block $label10 (result (ref $#Top)) (result (ref $Object))
                          block $label11 (result externref)
                            try_table
                              global.get $"\"try js\""
                              call $print
                              ref.null none
                              drop
                              br $label5
                            end
                            unreachable
                          end
                          local.set $var8
                          local.get $var8
                          call $boxJsException
                          local.set $var5
                          local.get $var8
                          call $jsExceptionStackTrace
                          local.set $var4
                          local.get $var0
                          struct.get $_AsyncSuspendState $_currentException
                          local.set $var6
                          local.get $var0
                          struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                          local.set $var7
                          local.get $var0
                          local.get $var5
                          struct.set $_AsyncSuspendState $_currentException
                          local.get $var0
                          local.get $var4
                          struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                          br $label7
                        end
                        local.set $var4
                        local.set $var5
                        local.get $var0
                        struct.get $_AsyncSuspendState $_currentException
                        local.set $var6
                        local.get $var0
                        struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                        local.set $var7
                        local.get $var0
                        local.get $var5
                        struct.set $_AsyncSuspendState $_currentException
                        local.get $var0
                        local.get $var4
                        struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                        br $label7
                      end
                    end $label7
                    local.get $var0
                    struct.get $_AsyncSuspendState $_currentException
                    ref.as_non_null
                    global.get $_InterfaceType
                    call $_isSubtype
                    i32.eqz
                    if
                      local.get $var0
                      struct.get $_AsyncSuspendState $_currentException
                      ref.as_non_null
                      local.get $var0
                      struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                      ref.as_non_null
                      throw $tag0
                    end
                    local.get $context
                    local.get $var0
                    struct.get $_AsyncSuspendState $_currentException
                    ref.cast $JSExternWrapper
                    struct.set $"<context file:///.../async_try_blocks.dart:27:33>" $field0
                    local.get $context
                    local.get $var0
                    struct.get $_AsyncSuspendState $_currentExceptionStackTrace
                    struct.set $"<context file:///.../async_try_blocks.dart:27:33>" $field1
                    global.get $"\"caught js \""
                    local.get $context
                    struct.get $"<context file:///.../async_try_blocks.dart:27:33>" $field0
                    call $JSStringImpl._interpolate2
                    call $print
                    ref.null none
                    drop
                    local.get $context
                    struct.get $"<context file:///.../async_try_blocks.dart:27:33>" $field0
                    drop
                    local.get $context
                    struct.get $"<context file:///.../async_try_blocks.dart:27:33>" $field1
                    drop
                    br $label6
                  end $label6
                  local.get $var0
                  local.get $var6
                  struct.set $_AsyncSuspendState $_currentException
                  local.get $var0
                  local.get $var7
                  struct.set $_AsyncSuspendState $_currentExceptionStackTrace
                  br $label5
                end $label5
              end $label4
              local.get $var0
              ref.null $#Top
              call $_AsyncSuspendState._complete
              ref.null none
              ref.null $#Top
              return
            end
            br $label0
          end
          unreachable
        end
        local.set $var11
        local.get $var11
        call $boxJsException
        local.set $var10
        local.get $var11
        call $jsExceptionStackTrace
        local.set $var9
        local.get $var0
        local.get $var10
        local.get $var9
        call $_AsyncSuspendState._completeError
        ref.null none
        ref.null $#Top
        return
      end
      local.set $var9
      local.set $var10
      local.get $var0
      local.get $var10
      local.get $var9
      call $_AsyncSuspendState._completeError
      ref.null none
      ref.null $#Top
      return
    end $label0
    unreachable
  )
  (func $Error._throw (param $var0 (ref $#Top)) (param $var1 (ref $Object)) <...>)
  (func $JSStringImpl._interpolate2 (param $value1 (ref null $#Top)) (param $value2 (ref null $#Top)) (result (ref $JSExternWrapper)) <...>)
  (func $StackTrace.current (result (ref $JavaScriptStack)) <...>)
  (func $_AsyncSuspendState._complete (param $this (ref $_AsyncSuspendState)) (param $value (ref null $#Top)) <...>)
  (func $_AsyncSuspendState._completeError (param $this (ref $_AsyncSuspendState)) (param $error (ref $#Top)) (param $stackTrace (ref $Object)) <...>)
  (func $_isSubtype (param $o (ref null $#Top)) (param $t (ref $_Type)) (result i32) <...>)
  (func $_makeFuture (param $var0 (ref $_Type)) (result (ref $_Future)) <...>)
  (func $_newAsyncSuspendState (param $resume (ref $type0)) (param $context structref) (param $future (ref $_Future)) (result (ref $_AsyncSuspendState)) <...>)
  (func $boxJsException (param $ref externref) (result (ref $#Top)) <...>)
  (func $jsExceptionStackTrace (param $ref externref) (result (ref $JavaScriptStack)) <...>)
  (func $print (param $object (ref null $#Top)) <...>)
  (func $testAsyncTryCatch (result (ref $_Future))
    (local $var0 (ref null $"<context file:///.../async_try_blocks.dart:16:31>"))
    (local $asyncState (ref $_AsyncSuspendState))
    struct.new_default $"<context file:///.../async_try_blocks.dart:16:31>"
    local.set $var0
    global.get $global0
    local.get $var0
    global.get $_TopType
    call $_makeFuture
    call $_newAsyncSuspendState
    local.set $asyncState
    local.get $asyncState
    ref.null $#Top
    ref.null $#Top
    ref.null $Object
    call $"testAsyncTryCatch inner"
    drop
    local.get $asyncState
    struct.get $_AsyncSuspendState $_future
    return
  )
  (func $testAsyncTryCatchJs (result (ref $_Future))
    (local $var0 (ref null $"<context file:///.../async_try_blocks.dart:27:33>"))
    (local $asyncState (ref $_AsyncSuspendState))
    struct.new_default $"<context file:///.../async_try_blocks.dart:27:33>"
    local.set $var0
    global.get $global2
    local.get $var0
    global.get $_TopType
    call $_makeFuture
    call $_newAsyncSuspendState
    local.set $asyncState
    local.get $asyncState
    ref.null $#Top
    ref.null $#Top
    ref.null $Object
    call $"testAsyncTryCatchJs inner"
    drop
    local.get $asyncState
    struct.get $_AsyncSuspendState $_future
    return
  )
)