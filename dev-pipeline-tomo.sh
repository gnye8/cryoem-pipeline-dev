#!/bin/bash -e


#load modules 
IMOD_VERSION="5.1.11"
IMOD_LOAD="imod/${IMOD_VERSION}" #update version
ARETOMO_VERSION="2.3.0"
ARETOMO_LOAD="aretomo/${ARETOMO_VERSION}"

#mode but tomo

# GENERATE
# select mode/task and define terms
MODE=${MODE:-tomo} 
TASK=${TASK:-all} # task options: generate 3D reconstruction / generate preview

# SCOPE PARAMS (set by the microscopes)
CS=${CS:-2.7}
KV=${KV:-300}
APIX=${APIX}
SUPERRES=${SUPERRES:-0}

#ARETOMO PARAMETERS


# READ MDOC
MDOC=${MDOC}

#help function: explains required and optional arguments 
usage() {
  cat <<__EOF__
Usage: $0 MICROGRAPH_FILE

Mandatory Arguments:
  [-a|--apix FLOAT]            use specified pixel size
  [-d|--fmdose FLOAT]          use specified fmdose in calculations

Optional Arguments:
  [-g|--gainref GAINREF_FILE]  use specificed gain reference file
  [-d|--defect DEFECT_FILE]    use specificed defect reference file
  [-b|--basename STR]          output files names with specified STR as prefix
  [-k|--kev INT]               input micrograph was taken with INT keV microscope
  [-s|--superres]              input micrograph was taken in super-resolution mode (so we should half the number of pixels)
  [-p|--phase-plate]           input microgrpah was taken using a phase plate (so we should calculate the phase)
  [-f|--force]                 reprocess all steps (ignore existing results).
  [-m|--mode [spa|tomo]]       pipeline to use: single particle analysis of tomography
  [-t|--task sum|align|pick|all] what to process; sum the stack, align the stack; just particle pick or all

__EOF__
}

main() {

  #allows user to use short options instead of long options
  for arg in "$@"; do
    shift
    case "$arg" in
      "--help")    set -- "$@" "-h";;
      "--gainref") set -- "$@" "-g";;
      "--defect") set -- "$@" "-d";;
      "--basename") set -- "$@" "-b";;
      "--force")   set -- "$@" "-F";;
      "--apix")    set -- "$@" "-a";;
      "--fmdose")  set -- "$@" "-d";;
      "--kev")     set -- "$@" "-k";;
      "--superres") set -- "$@" "-s";;
      "--phase-plate") set -- "$@" "-p";;
      "--mode")    set -- "$@" "-m";;
      "--task")    set -- "$@" "-t";;
      "--mdoc")    set -- "$@" "-c";;
      "--parallel")    set -- "$@" "-l";;
      *)           set -- "$@" "$arg";;
   esac
  done

#assigning command line flags to variables
  while getopts "Fhspm:t:l:g:b:a:d:k:e:c:" opt; do
    case "$opt" in
    g) GAINREF_FILE="$OPTARG";;
    d) DEFECT_FILE="$OPTARG";;
    b) BASENAME="$OPTARG";;
    a) APIX="$OPTARG";;
    d) FMDOSE="$OPTARG";;
    k) KV="$OPTARG";;
    s) SUPERRES=1;;
    p) PHASE_PLATE=1;;
    F) FORCE=1;;
    m) MODE="$OPTARG";;
    t) TASK="$OPTARG";;
    c) MDOC="$OPTARG";;
    l) PARALLEL="$OPTARG";;
    h) usage; exit 0;;
    ?) usage; exit 1;;
    esac
  done

  # read from mdocs
  if [[ "$MODE" == "tomo" && -z $MDOC ]]; then
    echo "Need mdoc filepath [-c|--mdoc] to continue..."
    usage
    exit 1
  fi
  if [ -e "${MDOC}" ]; then #the called functions don't exist anymore
    KV=${KV:-$(get_mdoc_voltage)}
    APIX=${APIX:-$(get_mdoc_apix)}
    FMDOSE=${FMDOSE:-$(get_mdoc_fmdose)}
  fi


#ensure all required variables are defined !! 
if [ -z $APIX ]; then # doesn't allow for apix to be undefined, exits if it is
    echo "Need pixel size [-a|--apix] to continue..."
    usage
    exit 1
  fi
}

#alternative sps pipeline
do_spa()
{

  if [ ${NO_PREAMBLE} -eq 0  ]; then
    do_prepipeline

    if [[ "$TASK" == "align" || "$TASK" == "sum" || "$TASK" == "all" ]]; then
      local force=${FORCE}
      if [ ${NO_FORCE_GAINREF} -eq 1 ]; then 
        FORCE=0
      fi
      do_gainref
      FORCE=$force
    fi
  else
    # still need to determine correct gainref
    local force=${FORCE}
    FORCE=0
    GAINREF_FILE=$(process_gainref "$GAINREF_FILE") || exit $?
    FORCE=$force
  fi

  # start doing something!
  echo "single_particle_analysis:"

  if [[ "$TASK" == "align" || "$TASK" == "all" ]]; then
    do_spa_align
  fi
  if [[ "$TASK" == "sum" || "$TASK" == "all" ]]; then
    do_spa_sum
  fi

  if [[ "$TASK" == "pick" || "$TASK" == "all" ]]; then
    # get the assumed pick file name
    if [ -z $ALIGNED_FILE ]; then
      ALIGNED_FILE=$(align_file ${MICROGRAPH})  || exit $?
    fi
    do_spa_pick
  fi

  if [[ "$TASK" == "preview" || "$TASK" == "all" ]]; then
    echo "  - task: preview"
    local start=$(date +%s.%N)
    # need to guess filenames
    if [ "$TASK" == "preview" ]; then
      ALIGNED_DW_FILE=$(align_dw_file ${MICROGRAPH}) || exit $?
      #echo "ALIGNED_DW_FILE: $ALIGNED_DW_FILE"
      ALIGNED_CTF_FILE=$(align_ctf_file "${MICROGRAPH}") || exit $?
      #echo "ALIGNED_CTF_FILE: $ALIGNED_CTF_FILE"
      PARTICLE_FILE=$(particle_file ${ALIGNED_DW_FILE}) || exit $?
      #echo "PARTICLE_FILE: $PARTICLE_FILE"
      SUMMED_CTF_FILE=$(sum_ctf_file "${MICROGRAPH}") || exit $?
      # remove the _sum bit if SUMMED_FILE defined
      if [ ! -z $SUMMED_FILE ]; then
        SUMMED_CTF_FILE="${SUMMED_CTF_FILE%_sum_ctf.mrc}_ctf.mrc"
        #>&2 echo "SUMMED CTF: $SUMMED_CTF_FILE"
      fi
      #echo "SUMMED_CTF_FILE: $SUMMED_CTF_FILE"
    fi
    PREVIEW_FILE=$(generate_preview) || exit $?
    echo "    files:"
    dump_file_meta "${PREVIEW_FILE}" || exit $?
    local duration=$( awk '{print $2-$1}' <<< "$start $(date +%s.%N)" )
    echo "    duration: $duration"
    echo "    executed_at: " $(date --utc +%FT%TZ -d @$start)
  fi

}

# create a do_tomo function
#based on assigned tasks will direct code to nesscary funcs
#- reconstruct - aretomo
#- generate preview - mrc2mp4
#- all

# write out record of data
do_prepipeline()
{
  echo "pre-pipeline:"

  # other params
  echo "  - task: input"
  echo "    data:"
  echo "      apix: ${APIX}"
  echo "      fmdose: ${FMDOSE}"
  echo "      astigmatism: ${CS}"
  echo "      kev: ${KV}"
  echo "      amplitude_contrast: ${AMPLITUDE_CONTRAST}"
  echo "      super_resolution: ${SUPERRES}"
  echo "      phase_plate: ${PHASE_PLATE}"

  # input micrograph
  if [[ "$MODE" == 'spa' ]] ; then
    echo "  - task: micrograph"
    echo "    files:"
    dump_file_meta "${MICROGRAPH}" || exit $?
  fi
}

# calls the process gain ref func
do_gainref()
{

  if [ ! -z "$GAINREF_FILE" ]; then
    # gainref
    echo "  - task: convert_gainref"
    local start=$(date +%s.%N)
    GAINREF_FILE=$(process_gainref "$GAINREF_FILE") || exit $?
    local duration=$( awk '{print $2-$1}' <<< "$start $(date +%s.%N)" )
    echo "    duration: $duration"
    echo "    executed_at: " $(date --utc +%FT%TZ -d @$start)
    echo "    files:"
    dump_file_meta "${GAINREF_FILE}" || exit $?
  fi
}

#create do_aretomo 
# print information about tilt series
# calls function inside of it, keep track of time
# 406 *


process_gainref()
{
  # read in a file and spit out the appropriate gainref to actually use via echo as path
  local input=$1
  local outdir=${2:-.}
  if [[ ${input:0:1} == "/" ]]; then outdir=""; else mkdir -p $outdir; fi
  if [[ ${input:0:2} == './' ]]; then input=${input#./}; fi

  >&2 echo
  
  local filename=$(basename -- "$input")
  local extension="${filename##*.}"
  local output="$outdir/${filename}"

  if [ ! -e "$input" ]; then
    >&2 echo "gainref file $input does not exist!"
    exit 4
  fi

  if [[ "$extension" -eq "dm4" ]]; then
  
    output="$outdir/${input%.$extension}.mrc"
    if [[ $FORCE -eq 1 || ! -e $output ]]; then
      >&2 echo "converting gainref file $input to $output..."
      module load ${IMOD_LOAD} || exit $?
      # assume $input is always superres, so scale down if not
      dm2mrc "$input" "$output"  1>&2 || exit $?
      if [[ "$SUPERRES" == "0" ]]; then
        >&2 echo "binning gain ref for non-superres $SUPERRES"
        >&2 newstack -bin 2 "$output" "/tmp/${filename%.$extension}.mrc" && mv "/tmp/${filename%.$extension}.mrc" "$output" || exit $?
      fi
    else
      >&2 echo "gainref file $output already exists"
    fi
  
  # TODO: this needs testing
  elif [[ "$extension" -eq 'mrc' && ! -e $output ]]; then
    
    >&2 echo "Error: output gainref file $output does not exist"
    
  fi
  
  echo $output
}


#calculating variables for AreTomo3
calculate_variables() {
  #calculate fm_dose and fm_int
  A_PIX=${APIX:-$(get_mdoc_apix)}
  K_V=${KV:-$(get_mdoc_voltage)}


  echo "$fm_dose $fm_int"
}

calculate_flip_gain() {
  #get the camera type from the mdoc file and determine if we need to flip the gain reference
  local camera_type=$(
  local mdoc=${1:-$MDOC}
}

# 
tomo_3D_reconstruction() { #1063 *
  # Commands
  module load ${ARETOMO_LOAD} || exit $?
  cmd=0
  prefix="[absolute path to tilt prefix]"
  gain_ref="[absolute path to gain reference]"
  outdir="/[absolute path to output directory]" #must be pre-created
  apix="{$APIX}"
  FM_DOSE=0.5 #[*define a function calculating this value*]
  FM_INT=1 #[*define a function calculate this value*]
  KV= ${KV-300}
  MC_PATCH=${5 5}
  SPLIT_SUM=${SPLIT_SUM:}
  VOLZ=${VOLZ:-1}
  ALIGNZ=${ALIGNZ:-0}

##default can be either left out (if in mdoc) or set here if not in mdoc
  AreTomo3 \ 
      -Cmd ${cmd} \
      -InPrefix "${prefix}" \
      -InSuffix ".mdoc" \
      -Gain "${gain_ref}" \
      -OutDir "${outdir}" \
      -Gpu 0 1 2 3 \
      -PixSize ${APIX} \
      -McPatch 5 5 \
      -FmInt ${fm_int} \
      -FmDose ${fm_dose} \
      -SplitSum 1 \
      -VolZ -1 \ #allow adjustment 
      -AlignZ 0 \
      -AtBin 4 \
      -FlipGain 1 \ #set variable conditional to camera type
      -AtPatch 4 4 \
      -Wbp 1 \
      -kV ${KV} \
      -Cs 2.7

}

#genrate mp4 function *1223*

#generate/dump file meta (smth similar) *1370*

#do_call_mp4 

set -e
main "$@"