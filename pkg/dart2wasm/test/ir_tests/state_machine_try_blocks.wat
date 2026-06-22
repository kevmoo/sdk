(module $module0
  (type $"<context file:///.../state_machine_try_blocks.dart:13:39>" <...>)
  (type $"<context file:///.../state_machine_try_blocks.dart:24:41>" <...>)
  (type $#Top <...>)
  (type $BoxedInt <...>)
  (type $JSExternWrapper <...>)
  (type $JavaScriptStack <...>)
  (type $Object <...>)
  (type $_InterfaceType <...>)
  (type $_SyncStarIterable <...>)
  (rec
    (type $_SyncStarIterator <...>)
    (type $_SuspendState <...>)
    (type $type0 <...>)
  )
  (type $_Type <...>)
  (tag $tag0 (param (ref $#Top) (ref $Object)))
  (global $"\"dart error\"" (ref $JSExternWrapper) <...>)
  (global $1 (ref $BoxedInt) <...>)
  (global $2 (ref $BoxedInt) <...>)
  (global $3 (ref $BoxedInt) <...>)
  (global $4 (ref $BoxedInt) <...>)
  (global $5 (ref $BoxedInt) <...>)
  (global $_InterfaceType (ref $_InterfaceType) <...>)
  (global $_InterfaceType (ref $_InterfaceType) <...>)
  (global $global0 (ref $type0) <...>)
  (global $global2 (ref $type0) <...>)
  (func $"testStateMachineTryCatch inner" (param $var0 (ref $_SuspendState)) (param $var1 (ref null $#Top)) (param $var2 (ref null $Object)) (result i32)
    (local $context (ref null $"<context file:///.../state_machine_try_blocks.dart:13:39>"))
    (local $targetIndex i32)
    (local $var3 (ref null $"<context file:///.../state_machine_try_blocks.dart:13:39>"))
    (local $var4 (ref $Object))
    (local $var5 (ref $#Top))
    (local $var6 (ref null $#Top))
    (local $var7 (ref null $Object))
    (local $var8 externref)
    (local $var9 (ref $Object))
    (local $var10 (ref $#Top))
    (local $var11 (ref null $#Top))
    (local $var12 (ref null $Object))
    (local $var13 externref)
    (local $var14 (ref $#Top))
    (local $var15 (ref $Object))
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
    (local $var33 (ref null $#Top))
    (local $var34 (ref null $Object))
    (local $var35 externref)
    (local $var36 (ref $Object))
    (local $var37 (ref $#Top))
    (local $var38 (ref null $#Top))
    (local $var39 (ref null $Object))
    (local $var40 externref)
    local.get $var0
    struct.get $_SuspendState $_targetIndex
    local.set $targetIndex
    loop $label0 i32
      block $label1
        block $label2
          block $label3
            block $label4
              block $label5
                block $label6
                  block $label7
                    block $label8
                      block $label9
                        block $label10
                          local.get $targetIndex
                          br_table $label10 $label9 $label8 $label7 $label6 $label5 $label4 $label3 $label2 $label1
                        end $label10
                        local.get $var0
                        struct.get $_SuspendState $_context
                        ref.cast null $"<context file:///.../state_machine_try_blocks.dart:13:39>"
                        local.set $context
                        struct.new_default $"<context file:///.../state_machine_try_blocks.dart:13:39>"
                        local.set $var3
                        local.get $var3
                        i64.const 0
                        struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                        block $label11
                          block $label12 (result (ref $#Top)) (result (ref $Object))
                            block $label13 (result externref)
                              try_table
                                block $label14
                                  block $label15 (result (ref $#Top)) (result (ref $Object))
                                    block $label16 (result externref)
                                      try_table
                                        local.get $var0
                                        struct.get $_SuspendState $_iterator
                                        global.get $1
                                        struct.set $_SyncStarIterator $_current
                                        local.get $var0
                                        local.get $var3
                                        struct.set $_SuspendState $_context
                                        local.get $var0
                                        i32.const 1
                                        struct.set $_SuspendState $_targetIndex
                                        i32.const 1
                                        return
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
                                    struct.get $_SuspendState $_currentException
                                    local.set $var6
                                    local.get $var0
                                    struct.get $_SuspendState $_currentExceptionStackTrace
                                    local.set $var7
                                    local.get $var0
                                    local.get $var5
                                    struct.set $_SuspendState $_currentException
                                    local.get $var0
                                    local.get $var4
                                    struct.set $_SuspendState $_currentExceptionStackTrace
                                    br $label8
                                  end
                                  local.set $var4
                                  local.set $var5
                                  local.get $var0
                                  struct.get $_SuspendState $_currentException
                                  local.set $var6
                                  local.get $var0
                                  struct.get $_SuspendState $_currentExceptionStackTrace
                                  local.set $var7
                                  local.get $var0
                                  local.get $var5
                                  struct.set $_SuspendState $_currentException
                                  local.get $var0
                                  local.get $var4
                                  struct.set $_SuspendState $_currentExceptionStackTrace
                                  br $label8
                                end
                                br $label11
                              end
                              unreachable
                            end
                            local.set $var13
                            local.get $var13
                            call $boxJsException
                            local.set $var10
                            local.get $var13
                            call $jsExceptionStackTrace
                            local.set $var9
                            local.get $var3
                            i64.const 2
                            struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                            local.get $var3
                            local.get $var10
                            struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                            local.get $var3
                            local.get $var9
                            struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                            local.get $var0
                            struct.get $_SuspendState $_currentException
                            local.set $var11
                            local.get $var0
                            struct.get $_SuspendState $_currentExceptionStackTrace
                            local.set $var12
                            local.get $var0
                            local.get $var10
                            struct.set $_SuspendState $_currentException
                            local.get $var0
                            local.get $var9
                            struct.set $_SuspendState $_currentExceptionStackTrace
                            br $label4
                          end
                          local.set $var9
                          local.set $var10
                          local.get $var3
                          i64.const 2
                          struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                          local.get $var3
                          local.get $var10
                          struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                          local.get $var3
                          local.get $var9
                          struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                          local.get $var0
                          struct.get $_SuspendState $_currentException
                          local.set $var11
                          local.get $var0
                          struct.get $_SuspendState $_currentExceptionStackTrace
                          local.set $var12
                          local.get $var0
                          local.get $var10
                          struct.set $_SuspendState $_currentException
                          local.get $var0
                          local.get $var9
                          struct.set $_SuspendState $_currentExceptionStackTrace
                          br $label4
                        end $label11
                      end $label9
                      block $label17
                        block $label18 (result (ref $#Top)) (result (ref $Object))
                          block $label19 (result externref)
                            try_table
                              local.get $var0
                              struct.get $_SuspendState $_context
                              ref.cast null $"<context file:///.../state_machine_try_blocks.dart:13:39>"
                              local.set $var3
                              global.get $"\"dart error\""
                              local.set $var14
                              call $StackTrace.current
                              local.set $var15
                              local.get $var3
                              i64.const 2
                              struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                              local.get $var3
                              local.get $var14
                              struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                              local.get $var3
                              local.get $var15
                              struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                              local.get $var14
                              local.get $var15
                              call $Error._throw
                              unreachable
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
                          local.get $var3
                          i64.const 2
                          struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                          local.get $var3
                          local.get $var17
                          struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                          local.get $var3
                          local.get $var16
                          struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                          local.get $var0
                          struct.get $_SuspendState $_currentException
                          local.set $var18
                          local.get $var0
                          struct.get $_SuspendState $_currentExceptionStackTrace
                          local.set $var19
                          local.get $var0
                          local.get $var17
                          struct.set $_SuspendState $_currentException
                          local.get $var0
                          local.get $var16
                          struct.set $_SuspendState $_currentExceptionStackTrace
                          br $label8
                        end
                        local.set $var16
                        local.set $var17
                        local.get $var3
                        i64.const 2
                        struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                        local.get $var3
                        local.get $var17
                        struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                        local.get $var3
                        local.get $var16
                        struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                        local.get $var0
                        struct.get $_SuspendState $_currentException
                        local.set $var18
                        local.get $var0
                        struct.get $_SuspendState $_currentExceptionStackTrace
                        local.set $var19
                        local.get $var0
                        local.get $var17
                        struct.set $_SuspendState $_currentException
                        local.get $var0
                        local.get $var16
                        struct.set $_SuspendState $_currentExceptionStackTrace
                        br $label8
                      end
                    end $label8
                    block $label20
                      block $label21 (result (ref $#Top)) (result (ref $Object))
                        block $label22 (result externref)
                          try_table
                            local.get $var3
                            local.get $var0
                            struct.get $_SuspendState $_currentException
                            ref.as_non_null
                            struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field3
                            local.get $var3
                            local.get $var0
                            struct.get $_SuspendState $_currentExceptionStackTrace
                            struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field4
                            local.get $var0
                            struct.get $_SuspendState $_iterator
                            global.get $2
                            struct.set $_SyncStarIterator $_current
                            local.get $var0
                            local.get $var3
                            struct.set $_SuspendState $_context
                            local.get $var0
                            i32.const 3
                            struct.set $_SuspendState $_targetIndex
                            i32.const 1
                            return
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
                        local.get $var3
                        i64.const 2
                        struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                        local.get $var3
                        local.get $var22
                        struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                        local.get $var3
                        local.get $var21
                        struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                        local.get $var0
                        struct.get $_SuspendState $_currentException
                        local.set $var23
                        local.get $var0
                        struct.get $_SuspendState $_currentExceptionStackTrace
                        local.set $var24
                        local.get $var0
                        local.get $var22
                        struct.set $_SuspendState $_currentException
                        local.get $var0
                        local.get $var21
                        struct.set $_SuspendState $_currentExceptionStackTrace
                        br $label4
                      end
                      local.set $var21
                      local.set $var22
                      local.get $var3
                      i64.const 2
                      struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                      local.get $var3
                      local.get $var22
                      struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                      local.get $var3
                      local.get $var21
                      struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                      local.get $var0
                      struct.get $_SuspendState $_currentException
                      local.set $var23
                      local.get $var0
                      struct.get $_SuspendState $_currentExceptionStackTrace
                      local.set $var24
                      local.get $var0
                      local.get $var22
                      struct.set $_SuspendState $_currentException
                      local.get $var0
                      local.get $var21
                      struct.set $_SuspendState $_currentExceptionStackTrace
                      br $label4
                    end
                  end $label7
                  block $label23
                    block $label24 (result (ref $#Top)) (result (ref $Object))
                      block $label25 (result externref)
                        try_table
                          local.get $var0
                          struct.get $_SuspendState $_context
                          ref.cast null $"<context file:///.../state_machine_try_blocks.dart:13:39>"
                          local.set $var3
                          local.get $var3
                          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field3
                          drop
                          local.get $var3
                          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field4
                          drop
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
                      local.get $var3
                      i64.const 2
                      struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                      local.get $var3
                      local.get $var27
                      struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                      local.get $var3
                      local.get $var26
                      struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                      local.get $var0
                      struct.get $_SuspendState $_currentException
                      local.set $var28
                      local.get $var0
                      struct.get $_SuspendState $_currentExceptionStackTrace
                      local.set $var29
                      local.get $var0
                      local.get $var27
                      struct.set $_SuspendState $_currentException
                      local.get $var0
                      local.get $var26
                      struct.set $_SuspendState $_currentExceptionStackTrace
                      br $label4
                    end
                    local.set $var26
                    local.set $var27
                    local.get $var3
                    i64.const 2
                    struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                    local.get $var3
                    local.get $var27
                    struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                    local.get $var3
                    local.get $var26
                    struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                    local.get $var0
                    struct.get $_SuspendState $_currentException
                    local.set $var28
                    local.get $var0
                    struct.get $_SuspendState $_currentExceptionStackTrace
                    local.set $var29
                    local.get $var0
                    local.get $var27
                    struct.set $_SuspendState $_currentException
                    local.get $var0
                    local.get $var26
                    struct.set $_SuspendState $_currentExceptionStackTrace
                    br $label4
                  end
                end $label6
                block $label26
                  block $label27 (result (ref $#Top)) (result (ref $Object))
                    block $label28 (result externref)
                      try_table
                        local.get $var0
                        local.get $var28
                        struct.set $_SuspendState $_currentException
                        local.get $var0
                        local.get $var29
                        struct.set $_SuspendState $_currentExceptionStackTrace
                        br $label5
                      end
                      unreachable
                    end
                    local.set $var35
                    local.get $var35
                    call $boxJsException
                    local.set $var32
                    local.get $var35
                    call $jsExceptionStackTrace
                    local.set $var31
                    local.get $var3
                    i64.const 2
                    struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                    local.get $var3
                    local.get $var32
                    struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                    local.get $var3
                    local.get $var31
                    struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                    local.get $var0
                    struct.get $_SuspendState $_currentException
                    local.set $var33
                    local.get $var0
                    struct.get $_SuspendState $_currentExceptionStackTrace
                    local.set $var34
                    local.get $var0
                    local.get $var32
                    struct.set $_SuspendState $_currentException
                    local.get $var0
                    local.get $var31
                    struct.set $_SuspendState $_currentExceptionStackTrace
                    br $label4
                  end
                  local.set $var31
                  local.set $var32
                  local.get $var3
                  i64.const 2
                  struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                  local.get $var3
                  local.get $var32
                  struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                  local.get $var3
                  local.get $var31
                  struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                  local.get $var0
                  struct.get $_SuspendState $_currentException
                  local.set $var33
                  local.get $var0
                  struct.get $_SuspendState $_currentExceptionStackTrace
                  local.set $var34
                  local.get $var0
                  local.get $var32
                  struct.set $_SuspendState $_currentException
                  local.get $var0
                  local.get $var31
                  struct.set $_SuspendState $_currentExceptionStackTrace
                  br $label4
                end
              end $label5
              block $label29
                block $label30 (result (ref $#Top)) (result (ref $Object))
                  block $label31 (result externref)
                    try_table
                      local.get $var3
                      i64.const 0
                      struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                      br $label4
                    end
                    unreachable
                  end
                  local.set $var40
                  local.get $var40
                  call $boxJsException
                  local.set $var37
                  local.get $var40
                  call $jsExceptionStackTrace
                  local.set $var36
                  local.get $var3
                  i64.const 2
                  struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                  local.get $var3
                  local.get $var37
                  struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                  local.get $var3
                  local.get $var36
                  struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                  local.get $var0
                  struct.get $_SuspendState $_currentException
                  local.set $var38
                  local.get $var0
                  struct.get $_SuspendState $_currentExceptionStackTrace
                  local.set $var39
                  local.get $var0
                  local.get $var37
                  struct.set $_SuspendState $_currentException
                  local.get $var0
                  local.get $var36
                  struct.set $_SuspendState $_currentExceptionStackTrace
                  br $label4
                end
                local.set $var36
                local.set $var37
                local.get $var3
                i64.const 2
                struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
                local.get $var3
                local.get $var37
                struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
                local.get $var3
                local.get $var36
                struct.set $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
                local.get $var0
                struct.get $_SuspendState $_currentException
                local.set $var38
                local.get $var0
                struct.get $_SuspendState $_currentExceptionStackTrace
                local.set $var39
                local.get $var0
                local.get $var37
                struct.set $_SuspendState $_currentException
                local.get $var0
                local.get $var36
                struct.set $_SuspendState $_currentExceptionStackTrace
                br $label4
              end
            end $label4
            local.get $var0
            struct.get $_SuspendState $_iterator
            global.get $3
            struct.set $_SyncStarIterator $_current
            local.get $var0
            local.get $var3
            struct.set $_SuspendState $_context
            local.get $var0
            i32.const 7
            struct.set $_SuspendState $_targetIndex
            i32.const 1
            return
          end $label3
          local.get $var0
          struct.get $_SuspendState $_context
          ref.cast null $"<context file:///.../state_machine_try_blocks.dart:13:39>"
          local.set $var3
          local.get $var3
          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
          drop
          local.get $var3
          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
          drop
          local.get $var3
          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
          drop
          local.get $var3
          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
          i32.wrap_i64
          i32.eqz
          if
            br $label2
          end
          local.get $var3
          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
          i32.wrap_i64
          i32.const 1
          i32.eq
          if
            local.get $var0
            i32.const 9
            struct.set $_SuspendState $_targetIndex
            i32.const 0
            return
          end
          local.get $var3
          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
          i32.wrap_i64
          i32.const 2
          i32.eq
          if
            local.get $var3
            struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field1
            ref.as_non_null
            local.get $var3
            struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field2
            ref.as_non_null
            throw $tag0
          end
          local.get $var3
          struct.get $"<context file:///.../state_machine_try_blocks.dart:13:39>" $field0
          i32.wrap_i64
          i32.const 3
          i32.sub
          local.set $targetIndex
          br $label0
        end $label2
      end $label1
      local.get $var0
      i32.const 9
      struct.set $_SuspendState $_targetIndex
      i32.const 0
      return
    end $label0
    return
  )
  (func $"testStateMachineTryCatchJs inner" (param $var0 (ref $_SuspendState)) (param $var1 (ref null $#Top)) (param $var2 (ref null $Object)) (result i32)
    (local $context (ref null $"<context file:///.../state_machine_try_blocks.dart:24:41>"))
    (local $targetIndex i32)
    (local $var3 (ref null $"<context file:///.../state_machine_try_blocks.dart:24:41>"))
    (local $var4 (ref $Object))
    (local $var5 (ref $#Top))
    (local $var6 (ref null $#Top))
    (local $var7 (ref null $Object))
    (local $var8 externref)
    (local $var9 (ref $Object))
    (local $var10 (ref $#Top))
    (local $var11 (ref null $#Top))
    (local $var12 (ref null $Object))
    (local $var13 externref)
    local.get $var0
    struct.get $_SuspendState $_targetIndex
    local.set $targetIndex
    loop $label0 i32
      block $label1
        block $label2
          block $label3
            block $label4
              block $label5
                block $label6
                  block $label7
                    local.get $targetIndex
                    br_table $label7 $label6 $label5 $label4 $label3 $label2 $label1
                  end $label7
                  local.get $var0
                  struct.get $_SuspendState $_context
                  ref.cast null $"<context file:///.../state_machine_try_blocks.dart:24:41>"
                  local.set $context
                  struct.new_default $"<context file:///.../state_machine_try_blocks.dart:24:41>"
                  local.set $var3
                  block $label8
                    block $label9 (result (ref $#Top)) (result (ref $Object))
                      block $label10 (result externref)
                        try_table
                          local.get $var0
                          struct.get $_SuspendState $_iterator
                          global.get $4
                          struct.set $_SyncStarIterator $_current
                          local.get $var0
                          local.get $var3
                          struct.set $_SuspendState $_context
                          local.get $var0
                          i32.const 1
                          struct.set $_SuspendState $_targetIndex
                          i32.const 1
                          return
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
                      struct.get $_SuspendState $_currentException
                      local.set $var6
                      local.get $var0
                      struct.get $_SuspendState $_currentExceptionStackTrace
                      local.set $var7
                      local.get $var0
                      local.get $var5
                      struct.set $_SuspendState $_currentException
                      local.get $var0
                      local.get $var4
                      struct.set $_SuspendState $_currentExceptionStackTrace
                      br $label5
                    end
                    local.set $var4
                    local.set $var5
                    local.get $var0
                    struct.get $_SuspendState $_currentException
                    local.set $var6
                    local.get $var0
                    struct.get $_SuspendState $_currentExceptionStackTrace
                    local.set $var7
                    local.get $var0
                    local.get $var5
                    struct.set $_SuspendState $_currentException
                    local.get $var0
                    local.get $var4
                    struct.set $_SuspendState $_currentExceptionStackTrace
                    br $label5
                  end
                end $label6
                block $label11
                  block $label12 (result (ref $#Top)) (result (ref $Object))
                    block $label13 (result externref)
                      try_table
                        local.get $var0
                        struct.get $_SuspendState $_context
                        ref.cast null $"<context file:///.../state_machine_try_blocks.dart:24:41>"
                        local.set $var3
                        br $label2
                      end
                      unreachable
                    end
                    local.set $var13
                    local.get $var13
                    call $boxJsException
                    local.set $var10
                    local.get $var13
                    call $jsExceptionStackTrace
                    local.set $var9
                    local.get $var0
                    struct.get $_SuspendState $_currentException
                    local.set $var11
                    local.get $var0
                    struct.get $_SuspendState $_currentExceptionStackTrace
                    local.set $var12
                    local.get $var0
                    local.get $var10
                    struct.set $_SuspendState $_currentException
                    local.get $var0
                    local.get $var9
                    struct.set $_SuspendState $_currentExceptionStackTrace
                    br $label5
                  end
                  local.set $var9
                  local.set $var10
                  local.get $var0
                  struct.get $_SuspendState $_currentException
                  local.set $var11
                  local.get $var0
                  struct.get $_SuspendState $_currentExceptionStackTrace
                  local.set $var12
                  local.get $var0
                  local.get $var10
                  struct.set $_SuspendState $_currentException
                  local.get $var0
                  local.get $var9
                  struct.set $_SuspendState $_currentExceptionStackTrace
                  br $label5
                end
              end $label5
              local.get $var0
              struct.get $_SuspendState $_currentException
              ref.as_non_null
              global.get $_InterfaceType
              call $_isSubtype
              i32.eqz
              if
                local.get $var0
                struct.get $_SuspendState $_currentException
                ref.as_non_null
                local.get $var0
                struct.get $_SuspendState $_currentExceptionStackTrace
                ref.as_non_null
                throw $tag0
              end
              local.get $var3
              local.get $var0
              struct.get $_SuspendState $_currentException
              ref.cast $JSExternWrapper
              struct.set $"<context file:///.../state_machine_try_blocks.dart:24:41>" $field0
              local.get $var3
              local.get $var0
              struct.get $_SuspendState $_currentExceptionStackTrace
              struct.set $"<context file:///.../state_machine_try_blocks.dart:24:41>" $field1
              local.get $var0
              struct.get $_SuspendState $_iterator
              global.get $5
              struct.set $_SyncStarIterator $_current
              local.get $var0
              local.get $var3
              struct.set $_SuspendState $_context
              local.get $var0
              i32.const 3
              struct.set $_SuspendState $_targetIndex
              i32.const 1
              return
            end $label4
            local.get $var0
            struct.get $_SuspendState $_context
            ref.cast null $"<context file:///.../state_machine_try_blocks.dart:24:41>"
            local.set $var3
            local.get $var3
            struct.get $"<context file:///.../state_machine_try_blocks.dart:24:41>" $field0
            drop
            local.get $var3
            struct.get $"<context file:///.../state_machine_try_blocks.dart:24:41>" $field1
            drop
            br $label3
          end $label3
          local.get $var0
          local.get $var11
          struct.set $_SuspendState $_currentException
          local.get $var0
          local.get $var12
          struct.set $_SuspendState $_currentExceptionStackTrace
          br $label2
        end $label2
      end $label1
      local.get $var0
      i32.const 6
      struct.set $_SuspendState $_targetIndex
      i32.const 0
      return
    end
    return
  )
  (func $Error._throw (param $var0 (ref $#Top)) (param $var1 (ref $Object)) <...>)
  (func $StackTrace.current (result (ref $JavaScriptStack)) <...>)
  (func $_isSubtype (param $o (ref null $#Top)) (param $t (ref $_Type)) (result i32) <...>)
  (func $boxJsException (param $ref externref) (result (ref $#Top)) <...>)
  (func $jsExceptionStackTrace (param $ref externref) (result (ref $JavaScriptStack)) <...>)
  (func $testStateMachineTryCatch (result (ref $Object))
    (local $var0 (ref null $"<context file:///.../state_machine_try_blocks.dart:13:39>"))
    struct.new_default $"<context file:///.../state_machine_try_blocks.dart:13:39>"
    local.set $var0
    i32.const 31
    i32.const 0
    global.get $_InterfaceType
    local.get $var0
    global.get $global0
    struct.new $_SyncStarIterable
    return
  )
  (func $testStateMachineTryCatchJs (result (ref $Object))
    (local $var0 (ref null $"<context file:///.../state_machine_try_blocks.dart:24:41>"))
    struct.new_default $"<context file:///.../state_machine_try_blocks.dart:24:41>"
    local.set $var0
    i32.const 31
    i32.const 0
    global.get $_InterfaceType
    local.get $var0
    global.get $global2
    struct.new $_SyncStarIterable
    return
  )
)