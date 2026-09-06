#!/usr/bin/env bash
# ============================================================
# CC-EPUB v6.0 — 批量处理模块 (lib/batch.sh)
#
# 从主脚本 cc-epub.sh 抽离，使测试套件（仅 source lib/*.sh）
# 也能调用 CCEPUB_batch_main，解决 "command not found" 问题。
# 依赖: common.sh / args.sh / convert.sh（须先 source）
# ============================================================

# 防止重复加载
[ -n "${CCEPUB_BATCH_LOADED:-}" ] && return 0
CCEPUB_BATCH_LOADED=1

# ---- 导出供子 shell 使用的函数 ----
export -f CCEPUB_batch_main CCEPUB_batch_serial CCEPUB_batch_parallel 2>/dev/null || true

# ============================================================
# 批量处理主入口：CCEPUB_batch_main
# 前置条件: CFG_BATCH_DIR 已设置且为合法目录
# ============================================================
CCEPUB_batch_main() {
    step "批量处理模式：扫描目录 $CFG_BATCH_DIR ..."

    # 收集文件
    local BATCH_FILES=()
    while IFS= read -r -d '' f; do
        local fname
        fname=$(basename "$f")
        if [ -n "$CFG_EXCLUDE_PATTERN" ] && [[ "$fname" == $CFG_EXCLUDE_PATTERN ]]; then
            verbose "排除: $fname"
            continue
        fi
        if [ -n "$CFG_INCLUDE_PATTERN" ] && [[ ! "$fname" == $CFG_INCLUDE_PATTERN ]]; then
            verbose "跳过（不匹配 include）: $fname"
            continue
        fi
        BATCH_FILES+=("$f")
    done < <(find "$CFG_BATCH_DIR" -maxdepth 1 -type f -name "*.epub" -print0 2>/dev/null)

    if [ ${#BATCH_FILES[@]} -eq 0 ]; then
        error "目录中未找到匹配的 .epub 文件: $CFG_BATCH_DIR"
        return 1
    fi

    # 断点续转
    local CHECKPOINT_FILE="$CCEPUB_TMP/.batch_checkpoint"
    if [ "$CFG_RESUME" -eq 1 ] && [ -f "$CHECKPOINT_FILE" ]; then
        info "找到断点续转文件，跳过已完成的文件..."
        local RESUMED=0
        local NEW_BATCH=()
        for f in "${BATCH_FILES[@]}"; do
            local rpath
            rpath=$(realpath "$f" 2>/dev/null || echo "$f")
            if grep -qF "$rpath" "$CHECKPOINT_FILE" 2>/dev/null; then
                RESUMED=$((RESUMED + 1))
                verbose "跳过已完成: $(basename "$f")"
            else
                NEW_BATCH+=("$f")
            fi
        done
        BATCH_FILES=("${NEW_BATCH[@]}")
        info "断点续转：跳过 $RESUMED 个已完成文件，剩余 ${#BATCH_FILES[@]} 个待处理"
    fi

    # 跳过已存在
    if [ "$CFG_SKIP_EXISTING" -eq 1 ]; then
        local NEW_BATCH=()
        for f in "${BATCH_FILES[@]}"; do
            local fname name out_name out_path
            fname=$(basename "$f")
            name="${fname%.*}"
            out_name="${CFG_OUTPUT_PREFIX}${name}${CFG_OUTPUT_SUFFIX}.epub"
            out_path="$CFG_OUTPUT_DIR/$out_name"
            if [ -f "$out_path" ]; then
                verbose "跳过已存在: $out_name"
            else
                NEW_BATCH+=("$f")
            fi
        done
        BATCH_FILES=("${NEW_BATCH[@]}")
        info "跳过已存在的输出文件后，剩余 ${#BATCH_FILES[@]} 个待处理"
    fi

    local TOTAL_STEPS=${#BATCH_FILES[@]}
    if [ "$TOTAL_STEPS" -eq 0 ]; then
        error "没有需要处理的文件"
        return 1
    fi

    info "找到 ${TOTAL_STEPS} 个 EPUB 文件待处理"
    info "转换模式: $CFG_MODE | 设备: $CFG_DEVICE | 并行: $CFG_PARALLEL_JOBS | 超时: ${CFG_TIMEOUT}s | 重试: $CFG_RETRY_COUNT"

    # 构建子任务参数
    CCEPUB_build_child_args

    # 并行处理
    if [ "$CFG_PARALLEL_JOBS" -gt 1 ]; then
        CCEPUB_batch_parallel
    else
        CCEPUB_batch_serial
    fi

    # 清理断点续转文件（全部成功后）
    if [ "$CFG_RESUME" -eq 1 ] && [ "$BATCH_FAILED" -eq 0 ]; then
        rm -f "$CHECKPOINT_FILE"
        info "所有文件处理完成，已清除断点续转记录"
    fi

    echo ""
    step "批量处理完成！"
    info "成功: $BATCH_SUCCESS | 失败: $BATCH_FAILED | 总计: $TOTAL_STEPS"

    if [ "$CFG_SHOW_STATS" -eq 1 ]; then
        echo ""
        info "=== 批量处理统计 ==="
        info "总文件数: $TOTAL_STEPS"
        info "成功: $BATCH_SUCCESS"
        info "失败: $BATCH_FAILED"
        if [ "$TOTAL_STEPS" -gt 0 ]; then
            local SUCCESS_RATE=$((BATCH_SUCCESS * 100 / TOTAL_STEPS))
            info "成功率: ${SUCCESS_RATE}%"
        fi
    fi
}

# ---- 串行处理 ----
CCEPUB_batch_serial() {
    BATCH_SUCCESS=0
    BATCH_FAILED=0
    local CURRENT_STEP=0

    for epub in "${BATCH_FILES[@]}"; do
        CURRENT_STEP=$((CURRENT_STEP + 1))
        echo ""
        info "----------------------------------------------"
        info "[$CURRENT_STEP/$TOTAL_STEPS] 正在处理: $(basename "$epub")"

        local ATTEMPT=0
        local MAX_ATTEMPT=$((CFG_RETRY_COUNT + 1))
        local SUCCESS=0
        while [ "$ATTEMPT" -lt "$MAX_ATTEMPT" ]; do
            ATTEMPT=$((ATTEMPT + 1))
            if CCEPUB_convert "$epub"; then
                SUCCESS=1
                break
            else
                if [ "$ATTEMPT" -lt "$MAX_ATTEMPT" ]; then
                    warn "处理失败，第 $ATTEMPT/$MAX_ATTEMPT 次重试..."
                fi
            fi
        done

        if [ "$SUCCESS" -eq 1 ]; then
            BATCH_SUCCESS=$((BATCH_SUCCESS + 1))
        else
            BATCH_FAILED=$((BATCH_FAILED + 1))
            warn "处理失败（已重试 $CFG_RETRY_COUNT 次）: $(basename "$epub")"
        fi

        # 断点续转记录（flock 保证并发安全，串行下也无害）
        if [ "$CFG_RESUME" -eq 1 ]; then
            mkdir -p "$CCEPUB_TMP"
            local rpath
            rpath=$(realpath "$epub" 2>/dev/null || echo "$epub")
            (
                flock 9
                echo "$rpath" > "$CHECKPOINT_FILE"
            ) 9>"$CHECKPOINT_FILE.lock" 2>/dev/null || echo "$rpath" >> "$CHECKPOINT_FILE" 2>/dev/null || true
        fi
    done
}

# ---- 并行处理（信号量池模式）----
CCEPUB_batch_parallel() {
    BATCH_SUCCESS=0
    BATCH_FAILED=0
    local JOB_DIR="$CCEPUB_TMP/.batch_jobs_$$"
    rm -rf "$JOB_DIR"
    mkdir -p "$JOB_DIR"

    step "并行处理模式：$CFG_PARALLEL_JOBS 个并发任务"

    # 导出变量供子 shell 使用
    export CCEPUB_LIB_DIR CFG_MODE CFG_ENCODING CFG_TIMEOUT CFG_RETRY_COUNT \
           CFG_OUTPUT_DIR CFG_OUTPUT_PREFIX CFG_OUTPUT_SUFFIX CFG_DEVICE \
           CFG_ADD_INDENT CFG_FORCE_HORIZONTAL CFG_COMPRESS_IMAGES CFG_KINDLE_OPT \
           CFG_DRY_RUN CFG_VERBOSE CFG_QUIET CFG_REBUILD_TOC CCEPUB_VERSION

    local running=0
    local pids=()

    for epub in "${BATCH_FILES[@]}"; do
        local JOB_ID
        JOB_ID=$(basename "$epub" .epub | tr '/' '_')

        # 启动后台任务
        (
            source "$CCEPUB_LIB_DIR/common.sh"
            source "$CCEPUB_LIB_DIR/args.sh"
            source "$CCEPUB_LIB_DIR/convert.sh"
            source "$CCEPUB_LIB_DIR/batch.sh"
            CCEPUB_convert "$epub" > "$JOB_DIR/${JOB_ID}.log" 2>&1
            echo $? > "$JOB_DIR/${JOB_ID}.status"
        ) &
        pids+=($!)
        running=$((running + 1))

        # 信号量：达到并发上限则等待任意一个完成
        if [ "$running" -ge "$CFG_PARALLEL_JOBS" ]; then
            local finished_pid
            finished_pid=$(wait -n "${pids[@]}" 2>/dev/null || true)
            # 更新 pid 列表
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            pids=("${new_pids[@]}")
            running=${#pids[@]}
        fi
    done

    # 等待剩余任务
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # 统计结果
    local status_file
    for status_file in "$JOB_DIR"/*.status; do
        [ -f "$status_file" ] || continue
        local code
        code=$(cat "$status_file")
        if [ "$code" -eq 0 ]; then
            BATCH_SUCCESS=$((BATCH_SUCCESS + 1))
        else
            BATCH_FAILED=$((BATCH_FAILED + 1))
            # 输出失败日志
            local lf="${status_file%.status}.log"
            [ -f "$lf" ] && cat "$lf" >&2
        fi
    done
    rm -rf "$JOB_DIR"
}

# ============================================================
# 交互式菜单（迁移自原 cc-epub.sh）
# ============================================================
CCEPUB_interactive_menu() {
    while true; do
        echo ""
        sep
        echo -e "  ${BOLD}CC-EPUB v${CCEPUB_VERSION} 交互式菜单${NC}"
        sep
        echo "  1) 转换单个文件"
        echo "  2) 批量转换目录"
        echo "  3) 检查 DRM"
        echo "  4) 查看配置"
        echo "  5) 退出"
        echo ""
        printf "${YELLOW}选择> ${NC}"
        read -r choice
        case "$choice" in
            1) CCEPUB_menu_convert_single ;;
            2) CCEPUB_menu_batch ;;
            3) CCEPUB_menu_check_drm ;;
            4) CCEPUB_ARGS_help ;;
            5) exit 0 ;;
            *) warn "无效选择" ;;
        esac
    done
}

CCEPUB_menu_convert_single() {
    printf "输入 EPUB 文件路径: "
    read -r epub_path
    [ -z "$epub_path" ] && return
    CFG_VERBOSE=1
    CFG_SHOW_STATS=1
    CCEPUB_convert "$epub_path"
}

CCEPUB_menu_batch() {
    printf "输入目录路径: "
    read -r dir_path
    [ -z "$dir_path" ] && return
    CFG_BATCH_DIR="$dir_path"
    CFG_SHOW_STATS=1
    CCEPUB_batch_main
}

CCEPUB_menu_check_drm() {
    printf "输入 EPUB 文件路径: "
    read -r epub_path
    [ -z "$epub_path" ] && return
    CFG_CHECK_DRM=1
    local DRM_FOUND=0
    if unzip -l "$epub_path" 2>/dev/null | grep -qi "encryption\|rights\|drmtype"; then DRM_FOUND=1; fi
    if [ "$DRM_FOUND" -eq 1 ]; then error "检测到 DRM 保护"; else success "未检测到 DRM"; fi
}
