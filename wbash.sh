#!/bin/bash

# Host supported: athena, zeus, local
WHOST=zeus
declare -A DEFAULT_WORKDIR=( ["athena"]=work ["zeus"]=work ["local"]='..' )
declare -A DEFAULT_QUEUE=( ["athena"]=poe_medium ["zeus"]=s_medium ["local"]=fake)
declare -A DEFAULT_QUEUE_SHORT=( ["athena"]=poe_short ["zeus"]=s_short ["local"]=fake)
declare -A DEFAULT_BSUB=( ["athena"]="bsub -R span[hosts=1] -sla SC_gams" ["zeus"]="bsub -R span[hosts=1]" ["local"]="local_bsub")
declare -A DEFAULT_NPROC=( ["athena"]=8 ["zeus"]=18 ["local"]=fake )
declare -A DEFAULT_SSH=( ["athena"]=ssh ["zeus"]=ssh ["local"]=local_ssh )
declare -A DEFAULT_RSYNC_PREFIX=( ["athena"]="athena:" ["zeus"]="zeus:" ["local"]="" )
declare -A DEFAULT_WDIR_SAME=( ["athena"]="" ["zeus"]="" ["local"]="TRUE" )

WAIT=T

wshow () {
    SCEN="$1"
    ${DEFAULT_SSH[$WHOST]} -T ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && sed -n 's/[*]/ /;s/ \+/ /g;/^Level SetVal/,/macro definitions/p;/macro definitions/q' ${SCEN}/${SCEN}.lst | cut -f 3,5 -d ' ' | sort -u -t\  -k1,1 | column -t -s' '" | perl -pe '$_ = "\e[92m$_\e[0m" if($. % 2)'
}

wrsync () {
    END_ARGS=FALSE
    RELATIVE="TRUE"
    WTARGET="$(wdirname)"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -a|-absolute)
                RELATIVE=""
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    RSYNC_ARGS=()
    [ -n "$RELATIVE" ] && RSYNC_ARGS=( --relative )
    echo /usr/bin/rsync -avzP --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r --exclude=.git "${RSYNC_ARGS[@]}" "${@}"
    /usr/bin/rsync -avzP --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r --exclude=.git "${RSYNC_ARGS[@]}" "${@}"
}

wdefault () {
    echo WHOST=${WHOST}
    echo DEFAULT_WORKDIR=${DEFAULT_WORKDIR[$WHOST]}
    echo DEFAULT_QUEUE=${DEFAULT_QUEUE[$WHOST]}
    echo DEFAULT_QUEUE_SHORT=${DEFAULT_QUEUE_SHORT[$WHOST]}
    echo DEFAULT_NPROC=${DEFAULT_NPROC[$WHOST]}
}

wsync () {
    [ -d ../witch-data ] || git clone git@github.com:witch-team/witch-data.git ../witch-data
    cd ../witch-data && git pull
    [ "$WHOST" = local ] || wup -t witch-data
    cd -
    [ -d ../witchtools ] || git clone git@github.com:witch-team/witchtools.git ../witchtools
    cd ../witchtools && git pull
    [ "$WHOST" = local ] || wup -t witchtools
    cd -    
    [ "$WHOST" = local ] || wup
}

wsetup () {
    wsync
    [ "$WHOST" = local ] && Rscript --vanilla tools/R/setup.R || wssh ${DEFAULT_BSUB[$WHOST]} -q ${DEFAULT_QUEUE[$WHOST]} -I -tty Rscript --vanilla tools/R/setup.R
}

wdirname () {
    # Name of directory under DEFAULT_WORKDIR to use for upload
    BRANCH="$(git branch --show-current)"
    PWD="$(basename $(pwd))"
    DESTDIR=""
    if [ -n "${DEFAULT_WDIR_SAME[$WHOST]}" ]; then
        DESTDIR="${PWD}"
    else
        [[ "$PWD" =~ .*${BRANCH} ]] && DESTDIR="${PWD}" || DESTDIR="${PWD}-${BRANCH}"
        DESTDIR=${DESTDIR%-master}
    fi
    echo "${DESTDIR}"
}


wup () {
    END_ARGS=FALSE
    ONLY_GIT="TRUE"
    WTARGET="$(wdirname)"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -a|-all)
                ONLY_GIT=""
                shift
                ;;
            -t|-target)
                WTARGET="$2"
                shift
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    MAYBE_SOURCE=()
    if [ "$#" -eq 0 ]; then
        MAYBE_SOURCE=( "./" )
    else
        [[ ! "${@: -1}" == [^-]* ]] && MAYBE_SOURCE=( "./" )
    fi
    RSYNC_ARGS=()
    TMPDIR=""
    if [ -n "$ONLY_GIT" ]; then
        TMPDIR="$(mktemp -d)"
        git -C . ls-files --exclude-standard -oi > ${TMPDIR}/excludes
        RSYNC_ARGS=( --exclude-from=$(echo ${TMPDIR}/excludes) )
    fi
    [ "$1" = '-h' ] && echo "Upload ./ to ${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/${WTARGET}, excluding non-git files" && return 1
    wrsync "${RSYNC_ARGS[@]}" ${@} ${MAYBE_SOURCE[@]} ${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/${WTARGET}
    [ -n "$ONLY_GIT" ] && rm -r "${TMPDIR}"
}

wdown () {
    END_ARGS=FALSE
    EXCLUDE_ALLDATATEMP="TRUE"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            -a|-all)
                EXCLUDE_ALLDATATEMP=""
                shift
                ;;   
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    RSYNC_ARGS=()
    [ -n "$EXCLUDE_ALLDATATEMP" ] && RSYNC_ARGS=(--exclude '*/all_data_*.gdx')
    wrsync "${RSYNC_ARGS[@]}" "${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)/./$1" .
}

wsub () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE[$WHOST]}
    NPROC=${DEFAULT_NPROC[$WHOST]}
    JOB_NAME=""
    BSUB_INTERACTIVE=""
    CALIB=""
    DEBUG=""
    VERBOSE=""
    RESDIR_CALIB=""
    USE_CALIB=""
    START=""
    STARTBOOST=""
    BAU=""
    FIX=""
    DEST="${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
    REG_SETUP=""
    DRY_RUN=""
    EXTRA_ARGS=""
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # WITCH
            -s|-start)
                START="$2"
                shift
                shift
                ;;   
            -S|-startboost)
                STARTBOOST=TRUE
                shift
                ;; 
            -r|-regions)
                REG_SETUP="$2"
                shift
                shift
                ;;
            -b|--bau)
                BAU="$2"
                shift
                shift
                ;;   
            -f|-gdxfix)
                FIX="$2"
                shift
                shift
                ;;
            -d|-debug)
                DEBUG=TRUE
                shift
                ;;            
            -v|-verbose)
                VERBOSE=TRUE
                shift
                ;;
            # CALIBRATION
            -c|-calib)
                CALIB=TRUE
                shift
                ;;
            -C|-resdircalib)
                RESDIR_CALIB=TRUE
                CALIB=TRUE
                shift
                ;;
            -u|-usecalib)
                USE_CALIB="$2"
                shift
                shift
                ;;
            # BSUB
            -D|-dryrun)
                DRY_RUN=TRUE
                shift
                ;;
            -j|-job)
                JOB_NAME="$2"
                shift
                shift
                ;;
            -i|-interactive)
                BSUB_INTERACTIVE=TRUE
                shift
                ;;
            -q|-queue)
                QUEUE="$2"
                shift
                shift
                ;;
            -n|-nproc)
                NPROC="$2"
                shift
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    [ -z "$JOB_NAME" ] && echo "Usage: wsub -j job-name [...]" && return 1
    [ -n "$CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --calibration=1"
    [ -n "$RESDIR_CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --write_tfp_file=resdir --calibgdxout=${JOB_NAME}/data_calib_${JOB_NAME}"
    if [ -n "$USE_CALIB" ]; then
        EXTRA_ARGS="${EXTRA_ARGS} --calibgdxout=${USE_CALIB}/data_calib_${USE_CALIB} --tfpgdx=${USE_CALIB}/data_tfp_${USE_CALIB}"
        [ -z "$BAU" ] && BAU="${USE_CALIB}/results_${USE_CALIB}.gdx"
        [ -z "$START" ] && START="${USE_CALIB}/results_${USE_CALIB}.gdx"
    fi
    if [ -n "$START" ]; then
        wssh test -f "$START"
        if [ ! $? -eq 0 ]; then
            if [ -f $START ]; then
                wrsync -a $START $(basename $START)
                START=$(basename $START)
                wrsync -a $START ${DEST}/
            else
                START="${START}/results_$(basename ${START}).gdx"
                wssh test -f "$START"
                if [ ! $? -eq 0 ]; then
                    echo "Unable to find $START"
                    return 1
                fi
            fi
        fi
        EXTRA_ARGS="${EXTRA_ARGS} --startgdx=${START%.gdx}"
        [ -z "$BAU" ] && BAU="${START}"
        [ -n "$CALIB" ] && EXTRA_ARGS="${EXTRA_ARGS} --tfpgdx=${START%.gdx}"
    fi
    if [ -n "$BAU" ]; then
        wssh test -f "$BAU"
        if [ ! $? -eq 0 ]; then
            if [ -f $BAU ]; then
                wrsync -a $BAU $(basename $BAU)
                BAU=$(basename $BAU)
                wrsync -a $BAU ${DEST}/
            else
                BAU="${BAU}/results_$(basename ${BAU}).gdx"
                wssh test -f "$BAU"
                if [ ! $? -eq 0 ]; then
                    echo "Unable to find $BAU"
                    return 1
                fi
            fi
        fi
        EXTRA_ARGS="${EXTRA_ARGS} --baugdx=${BAU%.gdx}"
    fi
    if [ -n "$FIX" ]; then
        wssh test -f "$FIX"
        if [ ! $? -eq 0 ]; then
            if [ -f $FIX ]; then
                wrsync -a $FIX $(basename $FIX)
                FIX=$(basename $FIX)
                wrsync -a $FIX ${DEST}/
            else            
                FIX="${FIX}/results_$(basename ${FIX}).gdx"
                wssh test -f "$FIX"
                if [ ! $? -eq 0 ]; then
                    echo "Unable to find $FIX"
                    return 1
                fi
            fi
        fi
        EXTRA_ARGS="${EXTRA_ARGS} --gdxfix=${FIX%.gdx}"
    fi
    [ -n "$DEBUG" ] && EXTRA_ARGS="${EXTRA_ARGS} --max_iter=1 --rerun=0 --only_solve=c_usa --parallel=false --holdfixed=0" || EXTRA_ARGS="${EXTRA_ARGS} --solvergrid=memory"
    [ -n "$VERBOSE" ] && EXTRA_ARGS="${EXTRA_ARGS} --verbose=1"
    [ -n "$STARTBOOST" ] && EXTRA_ARGS="${EXTRA_ARGS} --startboost=1"
    [ -n "$REG_SETUP" ] && EXTRA_ARGS="${EXTRA_ARGS} --n=${REG_SETUP}"
    wup
    BSUB="${DEFAULT_BSUB[$WHOST]}"
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="$BSUB -I -tty"
    echo ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && rm -rfv ${JOB_NAME}/{all_data*.gdx,*.{lst,err,out,txt}} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && $BSUB -J ${JOB_NAME} -n $NPROC -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"gams run_witch.gms ps=9999 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} ${EXTRA_ARGS} ${@}\""
    if [ -z "${DRY_RUN}" ]; then
        ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && rm -rfv ${JOB_NAME}/{all_data*.gdx,*.{lst,err,out,txt}} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && $BSUB -J ${JOB_NAME} -n $NPROC -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"gams run_witch.gms ps=9999 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} ${EXTRA_ARGS} ${@}\""
        if [ -n "$BSUB_INTERACTIVE" ]; then
            [ -n "$CALIB" ] && [ -z "$RESDIR_CALIB" ] && wdown data_${REG_SETUP}
            wdown ${JOB_NAME}
            notify-send "Done ${JOB_NAME}"
        fi
    fi
}

wdb () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE[$WHOST]}
    NPROC=${DEFAULT_NPROC[$WHOST]}
    JOB_NAME=""
    DEST="${DEFAULT_RSYNC_PREFIX[$WHOST]}${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)"
    DRY_RUN=""
    DB_OUT=""
    EXTRA_ARGS=""
    GDXBAU="bau/results_bau"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # WITCH
            -o|-dbout)
                DB_OUT="$2"
                shift
                shift
                ;;   
            -b|-baugdx)
                GDXBAU="$2"
                shift
                shift
                ;;   
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    SCEN="$1"
    shift
    PROCDIR="225_db_${SCEN}"
    [ -z "$DB_OUT" ] && DB_OUT="db_${SCEN}.gdx"
    BSUB="${DEFAULT_BSUB[$WHOST]} -I -tty"
    wup
    echo ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname)/${SCEN} && rm -rfv ${PROCDIR} db_* && mkdir -p ${PROCDIR} && $BSUB -J db_${SCEN} -n 1 -q $QUEUE -o db_${SCEN}.out -e db_${SCEN}.err \"gams ../post/database.gms ps=9999 pw=32767 gdxcompress=1 Output=db_${SCEN}.lst Procdir=${PROCDIR} --gdxout=results_${SCEN} --resdir=./ --gdxout_db=db_${SCEN} --baugdx=${GDXBAU} ${@}\""
    ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && rm -rfv ${PROCDIR} db_* && mkdir -p ${PROCDIR} && $BSUB -J db_${SCEN} -n 1 -q $QUEUE -o db_${SCEN}.out -e db_${SCEN}.err \"gams post/database.gms ps=9999 pw=32767 gdxcompress=1 Output=db_${SCEN}.lst Procdir=${PROCDIR} --gdxout=results_${SCEN} --resdir=${SCEN}/ --gdxout_db=db_${SCEN} --baugdx=${GDXBAU} ${@}\""
     wdown "${SCEN}/db*gdx"
     notify-send "Done db_${SCEN}"
}


wdata () {
    END_ARGS=FALSE
    QUEUE=${DEFAULT_QUEUE_SHORT[$WHOST]}
    BSUB_INTERACTIVE=""
    REG_SETUP="witch17"
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # BSUB
            -r|-regions)
                REG_SETUP="$2"
                shift
                shift
                ;;
            -i|-interactive)
                BSUB_INTERACTIVE=TRUE
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    JOB_NAME="data_${REG_SETUP}"
    wsync
    BSUB="${DEFAULT_BSUB[$WHOST]}"
    [ -n "$BSUB_INTERACTIVE" ] && BSUB="$BSUB -I -tty"
    ${DEFAULT_SSH[$WHOST]} ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && rm -rfv ${JOB_NAME}/${JOB_NAME}.{err,out} && mkdir -p ${JOB_NAME} && $BSUB -J ${JOB_NAME} -n 1 -q $QUEUE -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err \"Rscript --vanilla input/translate_witch_data.R -n ${REG_SETUP} ${@}\""
    if [ -n "$BSUB_INTERACTIVE" ]; then
        wdown ${JOB_NAME}
        notify-send "Done ${JOB_NAME}"
    fi
}


local_bsub () {
    END_ARGS=FALSE
    while [ $END_ARGS = FALSE ]; do
        key="$1"
        case $key in
            # BSUB
            -R)
                shift
                shift
                ;;
            -n)
                shift
                shift
                ;;
            -o)
                shift
                shift
                ;;
            -e)
                shift
                shift
                ;;
            -q)
                shift
                shift
                ;;
            -J)
                shift
                shift
                ;;
            -I)
                shift
                ;;
            -tty)
                shift
                ;;
            *)
                END_ARGS=TRUE
                ;;
        esac
    done
    eval "$@"
}

wssh () {
   ${DEFAULT_SSH[$WHOST]} -T ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && $@"
}

wsshq () {
   ${DEFAULT_SSH[$WHOST]} -T ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && \"${@}\""
}

wcheck () {
    JOB_NAME="$1"
    if [ -z "$JOB_NAME" ]; then
        ssh ${WHOST} bjobs -w
    else
        ssh ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && bpeek -f -J ${JOB_NAME}"
    fi
}

werr () {
    JOB_NAME="$1"
    if [ -z "$JOB_NAME" ]; then
        ssh ${WHOST} bjobs -w
    else
        ssh ${WHOST} "cd ${DEFAULT_WORKDIR[$WHOST]}/$(wdirname) && cat ${JOB_NAME}/errors_${JOB_NAME}.txt"
    fi
}

    
#     [ $# -lt 3 ] && echo 'Usage: wsub [job-name] [ncpu]exit 1
#     mkdir -p ${JOB_NAME}
#     bsub -J ${JOB_NAME} -I -R span[hosts=1] -sla SC_gams -n $(3) -q poe_medium -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err '$(2)'

# wrun-contained ()
# {
# RUN=$1
# NPROC=$2
# wrun_general serial_24h ${RUN} ${NPROC} ${@:3}
# }

# WITCH_CMD = rm -rfv ${JOB_NAME} 225_${JOB_NAME} && mkdir -p ${JOB_NAME} 225_${JOB_NAME} && gams run_witch.gms ps=9999 pw=32767 gdxcompress=1 Output=${JOB_NAME}/${JOB_NAME}.lst Procdir=225_${JOB_NAME} --nameout=${JOB_NAME} --resdir=${JOB_NAME}/ --gdxout=results_${JOB_NAME} $(2) && cat ${JOB_NAME}/errors_${JOB_NAME}.txt
# WCALIB = --calibration=1 --write_tfp_file=resdir --calibgdxout=${JOB_NAME}/tfp_${JOB_NAME}
# WDEBUG := 
# ## BSUB_CMD (1: job-name) (2: command to bsub) (3: number of cores)
# BSUB_CMD       = mkdir -p ${JOB_NAME} && bsub -J ${JOB_NAME} -I -R span[hosts=1] -sla SC_gams -n $(3) -q poe_medium -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err '$(2)'
# BSUB_CMD_QUEUE = mkdir -p ${JOB_NAME} && bsub -J ${JOB_NAME} -R span[hosts=1] -sla SC_gams -n $(3) -q poe_medium -o ${JOB_NAME}/${JOB_NAME}.out -e ${JOB_NAME}/${JOB_NAME}.err '$(2)'
# ## BSUB_WITCH (1: job-name) (2: extra arguments to gams run_witch.gms)
# BSUB_WITCH = $(call BSUB_CMD,${JOB_NAME},$(call RUN_WITCH,${JOB_NAME},$(2)),8)
# ## SSH_RUN (1: job-name) (2: cmd to run)
# SSH_CMD       = $(MAKE) up && ssh athena "cd work/witch-techno-cost/ && ${JOB_NAME}";$(RSYNC) athena:'work/witch-techno-cost/$(2)' ./
# SSH_CMD_QUEUE = $(MAKE) up && ssh athena "cd work/witch-techno-cost/ && ${JOB_NAME}"
# ## RUN_XXX (1: cmd to run) (2: job-name) (3: num cpus)
# RUN_SSH = $(call SSH_CMD,$(call BSUB_CMD,$(2),${JOB_NAME},$(3)),$(2))
# RUN_LOC = export R_GAMS_SYSDIR=/opt/gams && ${JOB_NAME}
# RUN_QUEUE = $(call SSH_CMD_QUEUE,$(call BSUB_CMD_QUEUE,$(2),${JOB_NAME},$(3)),$(2))




# wdump ()
# {
# WHAT=$1
# shift
# while [ "$1" != "" ]; do
#     for f in ${1}/all_data_temp*gdx; do
#         echo -e "\n\e[33m${f}:\e[0m" 1>&2 
#         gdxdump $f symb=${WHAT}
#     done
#     shift
# done
# }

# wtemp ()
# {
# workdir="$1"
# ngdx="$2"
# match="$3"
# for f in ${workdir}/all_data_temp_${match}*; do
# fbase=$(basename ${f}); fnameext=${fbase:14}; fname=temp_${fnameext%.gdx}
# until rsync ${f} ${fname}_1.gdx; do sleep 1; done
# ahash=$(md5sum ${fname}_1.gdx | cut -d' ' -f1)
# echo "${f} -> ${fname}_1.gdx (${ahash})"
# tail -n1 ${workdir}/errors_${match}*
# bhash=$ahash
# for i in $(seq 2 $ngdx); do
# while [ "$ahash" == "$bhash" ]; do sleep 4;bhash=$(md5sum ${f} | cut -d' ' -f1); done
# until rsync ${f} ${fname}_${i}.gdx; do sleep 1; done
# echo "${f} -> ${fname}_${i}.gdx (${bhash})"; tail -n1 ${workdir}/errors_${match}*
# ahash="${bhash}"
# done
# done
# }

# wclean ()
# {
# rm -rv 225*
# rm -v */*{lst,out,err}
# }

# wcleandir ()
# {
# SCENDIR=$1
# PROCDIR=225_${SCENDIR}
# if [ -d ${PROCDIR} ]; then
# rm -rf ${PROCDIR}/*
# else
# mkdir -p ${PROCDIR}
# fi
# if [ -d ${SCENDIR} ]; then
# rm ${SCENDIR}/{*lst,job*{out,err}}
# else
# mkdir -p ${SCENDIR}
# fi
# }

# wrun_general ()
# {
# QUEUE=$1
# RUN=$2
# NPROC=$3
# wcleandir ${RUN}
# mkdir -p ${RUN} 225_${RUN}
# EXTRA_ARGS=""
# PREV_CONV="$(gdxdump ${RUN}/results_${RUN}.gdx symb=stop_nash format=csv | tail -n1 | sed 's/[[:space:]]//g')"
# if [[ $PREV_CONV =~ ^1$ ]]; then
# [[ ! ${@:4} =~ startgdx ]] && EXTRA_ARGS="$EXTRA_ARGS --startgdx=${RUN}/results_${RUN} --calibgdx=${RUN}/results_${RUN} --tfpgdx=${RUN}/results_${RUN}"
# [[ ! ${@:4} =~ startgdx ]] && [[ ! ${@:4} =~ gdxfix ]] && EXTRA_ARGS="$EXTRA_ARGS --startboost=1"
# [[ ! ${@:4} =~ baugdx ]] && [[ ${RUN} =~ bau ]] && EXTRA_ARGS="$EXTRA_ARGS --baugdx=${RUN}/results_${RUN}"
# fi
# [ -z "$EXTRA_ARGS" ] || echo "AUTO EXTRA ARGS: $EXTRA_ARGS"
# bsub -n${NPROC} -J "$RUN" -R "span[hosts=1]" -q ${QUEUE} -o ${RUN}/job_${RUN}.out -e ${RUN}/job_${RUN}.err gams call_default.gms pw=32767 gdxcompress=1 Output="${RUN}/${RUN}.lst" Procdir=225_${RUN} --nameout="${RUN}" --resdir=$RUN/ --gdxout=results_${RUN} --gdxout_report=report_${RUN} --gdxout_start=start_${RUN} --verbose=1 --parallel=incore ${EXTRA_ARGS} ${@:4}
# }


# wrun6 ()
# {
# RUN=$1
# NPROC=$2
# wrun_general serial_6h ${RUN} ${NPROC} ${@:3}
# }

# wbrun ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wrun ${RUN} ${NPROC} --startgdx=${BASEGDX} --baugdx=${BASEGDX} --calibgdx=${BASEGDX} --tfpgdx=${BASEGDX} --startboost=1 ${@:4}
# }      

# wbrun6 ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wrun6 ${RUN} ${NPROC} --startgdx=${BASEGDX} --baugdx=${BASEGDX} --calibgdx=${BASEGDX} --tfpgdx=${BASEGDX} --startboost=1 ${@:4}
# }      

# wcrun ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wbrun ${RUN} ${NPROC} ${BASEGDX} --calibration=1 ${@:4}
# }      

# wfrun ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# wbrun ${RUN} ${NPROC} ${BASEGDX} --gdxfix=${BASEGDX} ${@:4}
# }      

# wtax ()
# {
# RUN=$1
# NPROC=$2
# BASEGDX=$3
# TAXSTARTPERIOD=$4
# TAXSTARTVAL=$5
# TAXGROWTHRATE=$6
# TFIX=$(expr ${TAXSTARTPERIOD} - 1)
# echo "Carbon tax starting in period ${TAXSTARTPERIOD} at ${TAXSTARTVAL} USD2005/tCO2 and growing at ${TAXGROWTHRATE} rate"
# wfrun ${RUN} ${NPROC} ${BASEGDX} --tfix=${TFIX} --policy=ctax --tax_start=${TAXSTARTPERIOD} --ctax2015=${TAXSTARTVAL} --ctaxgrowth=${TAXGROWTHRATE} ${@:7}
# }      

# wfind ()
# {
# grep -i "$1" *.gms */*.gms
# }

# gdiff ()
# {
#     type dwdiff &>nul 2>&1;
#     if [ $? -eq 0 ]; then
#         CMD=dwdiff;
#     else
#         if [ ! -f dwdiff ]; then
#             echo 'WARN: dwdiff tool not found... downloading'
#             curl http://os.ghalkes.nl/dist/dwdiff-2.1.0.tar.bz2 > dwdiff-2.1.0.tar.bz2
#             tar xjf dwdiff-2.1.0.tar.bz2 
#             cd dwdiff-2.1.0
#             ./configure
#             make all
#             mv dwdiff ../
#             cd ..
#             rm -rf dwdiff-2.1.0.tar.bz2 dwdiff-2.1.0
#             CMD=./dwdiff;
#         fi
#     fi;
#     SYMB=$1;
#     MATCHES=$2
#     DMPLIST=(one two);
#     IGDX=0;
#     AWKPARAM="/\"$(sed 's|,|[a-z]*"/ \&\& /"|g' <<<"${MATCHES}")[a-z]*\"/"
#     for GDX in ${@:3};
#     do
#         echo $GDX;
#         DMP=${GDX%.gdx}zzz.txt;
#         rm -fv "$DMP"
#         gdxdump $GDX symb=$SYMB format=csv | awk "$AWKPARAM" | sed 's/","/ /g;s/"//g;s/,/ /;' > "$DMP"
#         DMPLIST[IGDX]=$DMP;
#         let IGDX=IGDX+1;
#     done;
#     $CMD -c -L -d' ,.' ${DMPLIST[@]}
# }

# local_ssh () {
#     END_ARGS=FALSE
#     while [ $END_ARGS = FALSE ]; do
#         key="$1"
#         case $key in
#             -T)
#                 shift
#                 ;;
#             *)
#                 END_ARGS=TRUE
#                 ;;
#         esac
#     done
#     shift
#     eval "$@"
# }

# alias bw='bjobs -w'

# alias bwg='bjobs -w | egrep -i'

# alias bag='bjobs -aw | grep -i'

# alias bal='bjobs -aw | tail'

# alias bl='bjobs -l'

# alias blj='bjobs -l -J'

# alias bf='bpeek -f'

# alias bfj='bpeek -f -J'

# alias bq='bqueues | egrep "(QUEUE_NAME|serial|gams)"'

# alias bk='bkill'

# alias bkj='bkill -J'

# alias lsl='ls -lcth | head -n20'

# alias lsld='ls -lcth | egrep "^d" | grep -v " 225_" | head -n20'

