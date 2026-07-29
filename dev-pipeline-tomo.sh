#!/bin/bash -e


#load modules 
IMOD_VERSION="5.1.11"
IMOD_LOAD="imod/${IMOD_VERSION}" #update version
ARETOMO_VERSION="2.3.0"
ARETOMO_LOAD="aretomo/${ARETOMO_VERSION}"


# GENERATE
# select mode/task and define terms
MODE=${MODE:-tomo} 
TASK=${TASK:-all} # task options: generate 3D reconstruction / generate preview
FORCE=${FORCE:-0}
NO_FORCE_GAINREF=${NO_FORCE_GAINREF:-0}
NO_PREAMBLE=${NO_PREAMBLE:-0}

# SCOPE PARAMS (set by the microscopes)
CS=${CS:-2.7}
KV=${KV:-300}
APIX=${APIX}
SUPERRES=${SUPERRES:-0}
PHASE_PLATE=${PHASE_PLATE:-0}
AMPLITUDE_CONTRAST=${AMPLITUDE_CONTRAST:-0.1}

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
  [-e|--defect DEFECT_FILE]    use specificed defect reference file
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
      "--defect") set -- "$@" "-e";;
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
      *)           set -- "$@" "$arg";;
   esac
  done

#assigning command line flags to variables
#Grace: changed defect file variable to e so that two variables weren't using d
  while getopts "Fhspm:t:l:g:b:a:d:k:e:c:" opt; do
    case "$opt" in
    g) GAINREF_FILE="$OPTARG";;
    e) DEFECT_FILE="$OPTARG";;
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
  #don't need the called functions, we will use the values from the logbook passed
  #as arguments to the script, so we don't need to read from the mdoc file anymore


  #if [ -e "${MDOC}" ]; then #the called functions don't exist anymore
  #  KV=${KV:-$(get_mdoc_voltage)}
  #  APIX=${APIX:-$(get_mdoc_apix)}
  #  FMDOSE=${FMDOSE:-$(get_mdoc_fmdose)}
  #fi


#ensure all required variables are defined !! 
if [ -z $APIX ]; then # doesn't allow for apix to be undefined, exits if it is
    echo "Need pixel size [-a|--apix] to continue..."
    usage
    exit 1
  fi

#TO DO: add function to check if fmdose is defined
if [ -z $FMDOSE ]; then # doesn't allow for fmdose to be undefined, exits if it is
    echo "Need fmdose [-d|--fmdose] to continue..."
    usage
    exit 1
  fi


#TO DO: add function to check if all raw movies can be found in the same folder as the mdoc file
#if not, print an error message and exit
#make sure common path is defined

#TO DO: add function to kick things off based on the mode
#and the task specified by the user, and call the appropriate functions 
#assume the input to this script is a single mdoc file
#the function will ask if the mode is spa, then call do_spa function 
#if the mode is tomo, then call do_tomo function 
#else, print an error message and exit 
if [[ "$MODE" == "spa" ]]; then
    do_spa
  elif [[ "$MODE" == "tomo" ]]; then
    do_tomo
  else
    echo "Invalid mode specified: $MODE"
    usage
    exit 1
  fi
}


#alternative spa pipeline
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
  #TO DO: Grace will be deprecating the picking task for spa pipeline
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

  # input mdoc instead of micrograph
  if [[ "$MODE" == 'mdoc' ]] ; then
    echo "  - task: input_mdoc"
    echo "    files:"
    dump_file_meta "${MDOC}" || exit $?
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

#GRACE
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
  
  #added in support for gainref files ending in .gain 
  elif [[ "$extension" == "gain" ]]; then

    output="$outdir/${input%.$extension}.mrc"
    if [[ "$output" = ././* ]]; then output="${output:4}"; fi
    if [[ "$output" = ./* ]]; then output="${output:2}"; fi
    if [[ $FORCE -eq 1 || ! -e $output ]]; then
      >&2 echo "converting gainref file $input to $output..."
      module load ${IMOD_LOAD} || exit $?
      tif2mrc "$input" "$output" 1>&2 || exit $?
    else
      >&2 echo "gainref file $output already exists"
    fi
  
  # TODO: this needs testing
  elif [[ "$extension" -eq 'mrc' && ! -e $output ]]; then
    
    >&2 echo "Error: output gainref file $output does not exist"
    
  fi
  
  echo $output
}

#We don't need to calculate these variables because they will be provided by the user
#in the logbook and passed to the script as arguments!

#calculating variables for AreTomo3
#calculate_variables() {
#  #calculate fm_dose and fm_int
#  A_PIX=${APIX:-$(get_mdoc_apix)}
#  K_V=${KV:-$(get_mdoc_voltage)}


#  echo "$fm_dose $fm_int"
#}

#original script contains a variety of functions called motioncor_file, align_file, etc.
#the purpose of these functions is to generate an expected output file name 
#so that the script has unified naming conventions for the output files, and can check if they exist or not
#potentially we will need to add one for aretomo3 outputs
#can add this in later if it is needed


# TYNIQUE 
tomo_3D_reconstruction() { #1063 *
  # Commands
  module load ${ARETOMO_LOAD} || exit $?
  cmd=0
  prefix="[absolute path to tilt prefix]"
  gain_ref="[absolute path to gain reference]"
  outdir="/[absolute path to output directory]" #must be pre-created
  GPU={"0 1 2 3"}
  MCPATCH=${MCPATCH:-5 5}
  FMDOSE=0.5 
  FMINT=1
  SPLITSUM=${SPLITSUM:-1}
  VOLZ=${VOLZ:-1}
  ALIGNZ=${ALIGNZ:-0}
  ATBIN=${ATBIN:-4}
  FLIPGAIN=${FLIPGAIN:-1}
  ATPATCH=${ATPATCH:-4 4}
  WBP=${WBP:-1}

  AreTomo3 \ 
      -Cmd ${cmd} \
      -InPrefix "${prefix}" \
      -InSuffix ".mdoc" \
      -Gain "${gain_ref}" \
      -OutDir "${outdir}" \
      -Gpu ${GPU} \
      -PixSize ${APIX} \
      -McPatch ${MCPATCH} \
      -FmInt ${FMINT} \
      -FmDose ${FMDOSE} \
      -SplitSum ${SPLITSUM} \
      -VolZ ${VOLZ} \
      -AlignZ ${ALIGNZ} \
      -AtBin ${ATBIN} \
      -FlipGain ${FLIPGAIN} \
      -AtPatch ${ATPATCH} \
      -Wbp ${WBP} \
      -kV ${KV} \
      -Cs ${CS}

}

#genrate mp4 function *1223*
generate_preview() {
  local mrc_input="$1" # take mrc as first arg
  local outdir="${2:-.}" # if no output dir is given, put in current dir
  local frame_rate="${3:-4}" # default frame rate is 4 if not specified as arg

  # ensures mrc file is provided
  if [[ -z "$mrc_input" ]]; then
      >&2 echo "Error: No .mrc file provided as an argument."
      >&2 echo "Usage: $0 <mrc_file> [output_dir] [frame_rate]"
      exit 1
  fi
  
  # ensures if the input file exists
  if [ ! -e "$mrc_input" ]; then
    >&2 echo "input file $mrc_input not found!"
    exit  
  fi

  #create output directory
  local filename=$(basename -- "$mrc_input")
  local extension="${filename##*.}"
  local output="$outdir/${filename%.${extension}}.mp4"
  mkdir -p "$outdir"

  # checks if output files already exist, if so, exits to avoid overwriting (necessary? was in old code)
  if [ -e "$output" ]; then
    >&2 echo "output file $output already exists!"
    exit 1
  else
    # load imod
    module load ${IMOD_LOAD} || exit $?

    # imod command to compute min/max densities
    alterheader -mmm "$mrc_input"

    # reads density info from the header and extracts min/max values
    header_info=$(header "$mrc_input" 2>&1)
    min_density=$(grep -i 'Minimum Density' <<< "$header_info" | awk -F'\.\.\.' '{print $NF}' | awk '{print $1}')
    max_density=$(grep -i 'Maximum Density' <<< "$header_info" | awk -F'\.\.\.' '{print $NF}' | awk '{print $1}')

    echo "executing: .mrc to .tif conversion" 1>&2
    # imod command to convert .mrc to .tif 
    mrc2tif -C "${min_density}","${max_density}" "$mrc_input" "$outdir/${filename}" 
    echo "executing: .tif to .mp4 conversion" 1>&2
    # command to convert to mp4 from tiff 
    ffmpeg -pattern_type glob -framerate "${frame_rate}" -i "$outdir/${filename}"'*.tif' -pix_fmt yuv420p "$output" 1>&2
    echo "cleaning up .tif files" 1>&2

    # clean up tiff files
    rm -f "$outdir/${filename}"*.tif
  fi

  #makes sure output is there
  if [ ! -e "$output" ]; then
      >&2 echo "could not generate .mp4 file $output!"
      exit 4

  >&2 echo "done!"
  echo $output
  fi 
  }

#generate/dump file meta (smth similar) *1370*
generate_file_meta()
{
  local file="$1"
  if [ -h "$file" ]; then
    file=$(realpath "$file") || exit $?
  fi
  if [ ! -e "$file" ]; then
    >&2 echo "file $file does not exist!"
    exit 4
  fi
  local md5file="$1.md5"
  if [ -e "$md5file" ]; then
    >&2 echo "md5 checksum file $md5file already exists..."
  fi
  local md5=""
  >&2 echo "calculating checksum and stat for $file..."
  if [[ $FORCE -eq 1 || ! -e $md5file ]]; then
    md5=$(md5sum "$1" | tee "$md5file" | awk '{print $1}' ) || exit $?
  else
    md5=$(cat "$md5file" | cut -d ' ' -f 1) || exit $?
  fi
  stat=$(stat -c "%s/%y/%w" "$file") || exit $?
  mod=$(date --utc -d "$(echo $stat | cut -d '/' -f 2)"  +%FT%TZ) || exit $?
  create=$(echo $stat | cut -d '/' -f 3) || exit $?
  if [ "$create" == "-" ]; then create=$mod; fi
  size=$(echo $stat | cut -d '/' -f 1) || exit $?
  echo "file=\"$1\" checksum=$md5 size=$size modify_timestamp=$mod create_timestamp=$create"
}

dump_file_meta()
{
  if [ ! -e "$1" ]; then
    >&2 echo "File '$1' does not exist."
    exit 4
  fi
  echo "      - path: $1"
  out=$(generate_file_meta "$1") || exit $?
  eval "$out"
  echo "        checksum: $checksum"
  echo "        size: $size"
  echo "        modify_timestamp: $modify_timestamp"
  echo "        create_timestamp: $create_timestamp"
}

do_mp4() {
   
}

# create a do_tomo function
#based on assigned tasks will direct code to nesscary funcs
#- reconstruct - aretomo
#- generate preview - mrc2mp4
#- all
#create do_aretomo 
# print information about tilt series
# calls function inside of it, keep track of time
# 406 *
do_tomo() {
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
    if [[ "$GAINREF_FILE" != "" ]]; then
      GAINREF_FILE=$(process_gainref "$GAINREF_FILE") || exit $?
    fi
    FORCE=$force
  fi

  echo "tomographic_analysis:"
  if [[ "$TASK" == "reconstruct" || "$TASK" == "all" ]]; then
    echo "  - task: reconstruct"
    local start=$(date +%s.%N)
    tomo_3D_reconstruction
    local duration=$( awk '{print $2-$1}' <<< "$start $(date +%s.%N)" )
    echo "    duration: $duration"
    echo "    executed_at: " $(date --utc +%FT%TZ -d @$start)
  fi


  if [[ "$TASK" == "preview" || "$TASK" == "all" ]]; then
    echo "  - task: preview"
    local start=$(date +%s.%N)
    PREVIEW_FILE=$(generate_preview) || exit $?
    echo "    files:"
    dump_file_meta "${PREVIEW_FILE}" || exit $?
    local duration=$( awk '{print $2-$1}' <<< "$start $(date +%s.%N)" )
    echo "    duration: $duration"
    echo "    executed_at: " $(date --utc +%FT%TZ -d @$start)
  fi
}


set -e
main "$@"