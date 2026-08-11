#!/bin/bash -e


#load modules 
IMOD_VERSION="5.1.11"
IMOD_LOAD="imod/${IMOD_VERSION}" #update version
ARETOMO_VERSION="2.3.0"
ARETOMO_LOAD="aretomo3/${ARETOMO_VERSION}"


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
CMD=${CMD:-0}
GPU=${GPU:-0 1 2 3} #ask s3df guys about this
MCPATCH=${MCPATCH:-5 5}
#FMDOSE=0.5 # we will get rid of this as explicit input to the command so that aretomo will automatically pull it from the mdoc file 
#FMINT=1 # we will get rid of this as explicit input to the command so that aretomo will automatically pull it from the mdoc file 
SPLITSUM=${SPLITSUM:-1}
VOLZ=${VOLZ:-1}
ALIGNZ=${ALIGNZ:-0}
ATBIN=${ATBIN:-4}
FLIPGAIN=${FLIPGAIN:-1}
ATPATCH=${ATPATCH:-4 4}
WBP=${WBP:-1}

#help function: explains required and optional arguments 
usage() {
  cat <<__EOF__
Usage: $0 MDOC_FILE

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
    h) usage; exit 0;;
    ?) usage; exit 1;;
    esac
  done

  GAINREF_FILE="${GAINREF_FILE:-$GAINREF}"
  OUTDIR="${OUTDIR:-$OUTDIR}"

  MDOCS=("${@:$OPTIND}")
  MDOCS="${MDOCS:-$INPUT}"
  if [ ${#MDOCS[@]} -lt 1 ]; then
    echo "Need input mdoc MDOC_FILE to continue..."
    usage
    exit 1
  fi
  
  # read from mdocs
  #if [[ "$MODE" == "tomo" && -z $MDOC ]]; then
  #  echo "Need mdoc filepath [-c|--mdoc] to continue..."
  #  usage
  #  exit 1
  #fi

#ensure all required variables are defined !! 
if [ -z "$APIX" ]; then # doesn't allow for apix to be undefined, exits if it is
    echo "Need pixel size [-a|--apix] to continue..."
    usage
    exit 1
  fi

#TO DO: add function to check if fmdose is defined
if [ -z "$FMDOSE" ]; then # doesn't allow for fmdose to be undefined, exits if it is
    echo "Need fmdose [-d|--fmdose] to continue..."
    usage
    exit 1
  fi

#deal with this later
#ensure_all_files() {
#  local mdoc="$1"
#  local mdoc_dir=$(dirname "$mdoc")
#  local name
#  local prefix
#  local expected_files
#  #parse full tilt series path
#  name=$(awk '/SubFramePath = / { print $3; exit }' "$mdoc")
#  name=$(basename "$name")
#  name="${name%.mrc}"
#  #parse tilt series
#  prefix="${name%[0-9]*}"
#  # parse number of files
#  expected_files=$(echo "$name" | sed -E 's/.*_([0-9]+)_.*/\1/')
#  expected_files=$(printf '%03d' "$expected_files")

  #convert counted files to num with leading zeros to match file num format
  #counted_files=$(printf '%03d' "$(( $(grep -l "^${prefix}" "$mdoc_dir"/* 2>/dev/null | wc -l) + 1 ))") #this won't work 

  #check that there are at least as many files as expected 
  #if [[ "$counted_files" -lt "$expected_files" ]]; then
  #  >&2 echo "Error: all expected files not in $mdoc_dir!"
  #  exit 1
  #fi
#  
#}

#TO DO: add function to kick things off based on the mode
#and the task specified by the user, and call the appropriate functions 
#assume the input to this script is a single mdoc file
#the function will ask if the mode is spa, then call do_spa function 
#if the mode is tomo, then call do_tomo function 
#else, print an error message and exit 
for MDOC in ${MDOCS}; do

  # strip ./
  if [[ "$MDOC" = ./* ]]; then MDOC="${MDOC:2}"; fi
  if [[ "$MODE" == "tomo" ]]; then
      >&2 echo "MDOC: ${MDOC}"
      do_tomo
  elif [[ "$MODE" == "spa" ]]; then
      do_spa
  else
    echo "Invalid mode specified: $MODE"
    usage
    exit 1
  fi
done
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


#based on assigned tasks will direct code to necessary funcs
#- reconstruct - aretomo
#- generate preview - mrc2mp4
#- all
#create do_aretomo 
# print information about tilt series
# calls function inside of it, keep track of time
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
  #  ensure_all_files "$MDOC"
    echo "  - task: reconstruct"
    local start=$(date +%s.%N)
    # pass the current mdoc and gainref into the reconstruction function
    tomo_reconstruction "$MDOC" "$GAINREF_FILE" || exit $?
    #we also may want to have the dose weighted tomogram as the output so that we can use it as input for the generate_preview function
    TOMOGRAM=$(tomogram "$MDOC") || exit $?
    local duration=$( awk '{print $2-$1}' <<< "$start $(date +%s.%N)" )
    echo "    duration: $duration"
    echo "    executed_at: " $(date --utc +%FT%TZ -d @$start)
  fi

  if [[ "$TASK" == "preview" || "$TASK" == "all" ]]; then
    echo "  - task: preview"
    TOMOGRAM=$(tomogram "$MDOC") || exit $? 
    local start=$(date +%s.%N)
    local preview_path=$(generate_preview "$TOMOGRAM") || exit $? #should this output the mp4 file rather than putting it in the directory?
    echo "    files:"
    dump_file_meta "${preview_path}" || exit $?
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
  if [[ "$MODE" == 'tomo' ]] ; then
    echo "  - task: input_mdoc"
    echo "    files:"
    dump_file_meta "${MDOC}" || exit $?
  fi
}

function gen_template() {
  eval "echo \"$1\""
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
  local output="$outdir${filename}" #take off slash lets see what happens

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

#original script contains a variety of functions called motioncor_file, align_file, etc.
#the purpose of these functions is to generate an expected output file name 
#so that the script has unified naming conventions for the output files, and can check if they exist or not
#potentially we will need to add one for aretomo3 outputs
#can add this in later if it is needed


# TYNIQUE
tomo_reconstruction() {
  #prev tomo_3D
  nvidia-smi
  local input="${1:-$INPUT}"
  local gainref="${2:-$GAINREF}" 
  local outdir="${3:-$OUTDIR}"
  local prefix=${input%.*} # strip extension of mdoc

  # if [[ "$prefix" == "$filename" ]]; then
  #  prefix="$filename"
  # fi

  if [[ -z "$input" ]]; then
    >&2 echo "Error: no input mdoc provided for tomogram reconstruction."
    return 1
  fi

  if [[ ! -f "$input" ]]; then
    >&2 echo "Error: input mdoc $input does not exist."
    return 1
  fi

  mkdir -p $outdir

  >&2 echo "reconstructing tomogram from $input"
  
  local aretomo_cmd="
  AreTomo3 \
      -Cmd ${CMD} \
      -InPrefix ${prefix} \
      -InSuffix .mdoc \
      -Gain ${gainref} \
      -OutDir ${outdir} \
      -Gpu \"${GPU}\" \
      -PixSize $(echo $APIX | awk -v superres=$SUPERRES '{ if( superres=="1" ){ print $1/2 }else{ print $1 } }') \
      -McPatch ${MCPATCH} \
      -SplitSum ${SPLITSUM} \
      -VolZ ${VOLZ} \
      -AlignZ ${ALIGNZ} \
      -AtBin ${ATBIN} \
      -FlipGain ${FLIPGAIN} \
      -AtPatch ${ATPATCH} \
      -Wbp ${WBP} \
      -kV ${KV} \
      -Cs ${CS}
  "

  reconstruct_command=$(gen_template "$aretomo_cmd") || exit $?
  >&2 echo "executing:" $reconstruct_command
  module load ${ARETOMO_LOAD} || exit $?
  >&2 eval "$reconstruct_command"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    >&2 echo "Error: AreTomo3 exited with code $rc"
    return $rc
  fi


  local tomogram_mrc="$outdir/$(basename ${input%.*}).mrc" #change to find 

  if [[ ! -f "$tomogram_mrc" ]]; then
    >&2 echo "Warning: expected output $tomogram_mrc was not created."
    return 1
  fi
}

# find and return the reconstructed tomogram file
tomogram() {
  local input=$1
  local outdir="${2:-reconstructed/aretomo3/$ARETOMO_VERSION}"
  local filename=$(basename -- "$input")
  local prefix="${filename%.*}"
  if [[ "$prefix" == "$filename" ]]; then
    prefix="$filename"
  fi

  # check naming convention 
  local tomogram_mrc="$outdir/$(basename ${input%.*}).mrc"
  if [[ -f "$tomogram_mrc" ]]; then
    echo "$tomogram_mrc"
    return 0
  else
    >&2 echo "Error: no tomogram .mrc found in $outdir"
    return 1
  fi

  #maybe add something to find other *.mrc in case it doesn't find anything for whatever reason?

  echo "$tomogram_mrc"

}
generate_preview() {
  local mrc_input="$1" 
  local outdir="${2:-.}" # if no output dir is given, put in current dir
  local frame_rate="${3:-4}" # default frame rate is 4 if not specified as arg

  # ensures mrc file is provided
  if [[ -z "$mrc_input" ]]; then
      >&2 echo "Error: No .mrc file provided as an argument."
      >&2 echo "Usage: $0 <mrc_file> [output_dir] [frame_rate]"
      exit 1
  fi
  
  # ensures the input file exists
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
    local header_info=$(header "$mrc_input" 2>&1)
    local min_density=$(grep -i 'Minimum Density' <<< "$header_info" | awk -F'\.\.\.' '{print $NF}' | awk '{print $1}')
    local max_density=$(grep -i 'Maximum Density' <<< "$header_info" | awk -F'\.\.\.' '{print $NF}' | awk '{print $1}')

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

  # makes sure output is there
  if [ ! -e "$output" ]; then
    >&2 echo "could not generate .mp4 file $output!"
    exit 4
  fi

  >&2 echo "done!"
  echo "$output"
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

  local md5file="${1%.*}.md5"
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


set -e
main "$@"