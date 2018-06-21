#! /bin/bash

## Usage: ./runOffLHE.sh SIDMmumu_Mps-202_MZp-1p2_ctau-0p01.lhe.gz 0.1

export BASEDIR=`pwd`
LHE_f=$1
CTau_mm=$2
MGLHEDIR=${BASEDIR}/mgLHEs
HADRONIZER="externalLHEProducer_and_PYTHIA8_Hadronizer.py"
namebase=${LHE_f/.lhe.gz/}
nevent=1000

export VO_CMS_SW_DIR=/cvmfs/cms.cern.ch
source $VO_CMS_SW_DIR/cmsset_default.sh

export SCRAM_ARCH=slc6_amd64_gcc630
if ! [ -r CMSSW_9_4_4/src ] ; then
    scram p CMSSW CMSSW_9_4_4
fi
cd CMSSW_9_4_4/src
rm -rf *
mkdir -p Configuration/GenProduction/python/
cp ${BASEDIR}/conf/${HADRONIZER} Configuration/GenProduction/python/
zcat ${MGLHEDIR}/$1 > ${LHE_f/.gz/}
echo "    Replace lifetime for LHE.."
python ${BASEDIR}/replaceLHELifetime.py -i ${LHE_f/.gz/} -t ${CTau_mm}
eval `scram runtime -sh`
scram b -j 4

echo "1.) Generating GEN-SIM"
cmsDriver.py Configuration/GenProduction/python/${HADRONIZER} \
    --filein file:${LHE_f/.gz/} \
    --fileout file:${namebase}_GENSIM.root \
    --mc --eventcontent RAWSIM --datatier GEN-SIM \
    --conditions auto:phase1_2017_realistic --beamspot Realistic25ns13TeVEarly2017Collision \
    --step GEN,SIM --era Run2_2017 \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --python_filename ${namebase}_GENSIM_cfg.py --no_exec -n ${nevent} || exit $?;
cmsRun -p ${namebase}_GENSIM_cfg.py

echo "2.) Generating DIGI-RAW-HLT"
cmsDriver.py step1 \
    --filein file:${namebase}_GENSIM.root \
    --fileout file:${namebase}_DIGIRAWHLT.root \
    --era Run2_2017 --conditions 94X_mc2017_realistic_v10 \
    --mc --step DIGI,L1,DIGI2RAW,HLT:@relval2017 \
    --datatier GEN-SIM-DIGI-RAWHLTDEBUG --eventcontent FEVTDEBUGHLT \
    --number ${nevent} \
    --geometry DB:Extended --nThreads 8 \
    --python_filename ${namebase}_DIGIRAWHLT_cfg.py \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --no_exec || exit $?;
cmsRun -p ${namebase}_DIGIRAWHLT_cfg.py

echo "3.) Generating AOD"
cmsDriver.py step2 \
    --filein file:${namebase}_DIGIRAWHLT.root \
    --fileout file:${namebase}_AOD.root \
    --mc --eventcontent AODSIM --datatier AODSIM --runUnscheduled \
    --conditions auto:phase1_2017_realistic --step RAW2DIGI,L1Reco,RECO \
    --nThreads 8 --era Run2_2017 --python_filename ${namebase}_AOD_cfg.py --no_exec \
    --customise Configuration/DataProcessing/Utils.addMonitoring -n ${nevent} || exit $?;
cmsRun -p ${namebase}_AOD_cfg.py

echo "4.) Generating MINIAOD"
cmsDriver.py step3 \
    --filein file:${namebase}_AOD.root \
    --fileout file:${namebase}_MINIAOD.root \
    --mc --eventcontent MINIAODSIM --datatier MINIAODSIM --runUnscheduled \
    --conditions auto:phase1_2017_realistic --step PAT \
    --nThreads 8 --era Run2_2017 --python_filename ${namebase}_MINIAOD_cfg.py --no_exec \
    --customise Configuration/DataProcessing/Utils.addMonitoring -n ${nevent} || exit $?;
cmsRun -p ${namebase}_MINIAOD_cfg.py

echo "DONE."