#!/bin/bash
# geofence APR: ICC2 flow, post-layout simulation, ICV DRC
set -e
cd "$(dirname "$0")"
export VERDI_HOME=/mnt/nfs/opt/EDA/synopsys/verdi/cur
LIB=/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5
# tech file without the via*_fat bar-via contact codes (they fail VIA5.W.1; allowed only in seal rings)
[ -f tsmc13_CIC_nofat.tf ] || awk '/ContactCode.*_fat/{f=1} f&&/^}/{f=0;next} !f' $LIB/ICC2/tsmc13_CIC.tf > tsmc13_CIC_nofat.tf
mkdir -p rpt drc lvs
cp -n $LIB/icv/drc/ICV13S_8M.drc.rs drc/ 2>/dev/null
cp -n $LIB/icv/lvs/* lvs/ 2>/dev/null
for s in 01_init 02_pnr 03_out; do
  icc2_shell -f $s.tcl -output_log_file $s.log < /dev/null > /dev/null 2>&1
  grep -q "STAGE: ${s#*_} done" $s.log || { echo "FAIL $s"; grep "^Error" $s.log | head; exit 1; }
done

mkdir -p sim_post && cd sim_post
ln -sf ../out/geofence_apr.sdf geofence_syn.sdf
ln -sf ../../univ.data univ.data
vcs -R -full64 -sverilog -debug_access+all -kdb +vcs+fsdbon +define+SDF +maxdelays +neg_tchk \
  ../../tb.sv ../out/geofence_apr.v -v /mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5/Verilog/tsmc13_neg.v \
  -l vcs_post.log > /dev/null 2>&1 || true
grep -q "ALL PASS" vcs_post.log && echo "SIM: ALL PASS" || echo "SIM: FAIL"
cd ..

cd drc
icv -i ../out/geofence.gds -c geofence -host_init 4 ICV13S_8M.drc.rs > icv_drc.out 2>&1 || true
grep -m1 "RESULTS:" geofence.RESULTS
grep -E "violations? found" geofence.LAYOUT_ERRORS | grep -v " 0 violations" || true
cd ..

# LVS with standard cells as black boxes (the GDS only has phantom cell frames)
cd lvs
icv_nettran -outType SPICE -verilog ../out/geofence_apr_pg.v -outName verilog2spice.sp > nettran.out 2>&1
icv -vue -vueshortALL -create_lvs_short_outputALL -i ../out/geofence.gds -c geofence \
  -s verilog2spice.sp -stc geofence -sf SPICE -host_init 4 ICV_LVS.rs > icv_lvs.out 2>&1 || true
grep -m1 "LVS Compare Results" geofence.RESULTS
