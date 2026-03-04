#!/bin/bash
set -e
FILE=".github/workflows/cd-deploy.yml"

# Inject matrix strategy into deploy-staging
sed -i 's/  deploy-staging:/  deploy-staging:\n    strategy:\n      fail-fast: false\n      matrix: ${{ fromJson(needs.preflight.outputs.nodes_matrix) }}/g' $FILE
sed -i 's/name: Deploy to Staging/name: Deploy to Staging (\${{ matrix.name }})/g' $FILE

# Inject matrix into smoke-battery-staging
sed -i 's/  smoke-battery-staging:/  smoke-battery-staging:\n    strategy:\n      fail-fast: false\n      matrix: ${{ fromJson(needs.preflight.outputs.nodes_matrix) }}/g' $FILE
sed -i 's/name: Smoke Battery (Staging)/name: Smoke Battery (\${{ matrix.name }})/g' $FILE

# Inject matrix into backup
sed -i 's/  backup:/  backup:\n    strategy:\n      fail-fast: false\n      matrix: ${{ fromJson(needs.preflight.outputs.nodes_matrix) }}/g' $FILE
sed -i 's/name: Pre-deploy Backup/name: Pre-deploy Backup (\${{ matrix.name }})/g' $FILE

# Inject matrix into dora-metrics
sed -i 's/  dora-metrics:/  dora-metrics:\n    strategy:\n      fail-fast: false\n      matrix: ${{ fromJson(needs.preflight.outputs.nodes_matrix) }}/g' $FILE
sed -i 's/name: DORA Metrics/name: DORA Metrics (\${{ matrix.name }})/g' $FILE

# Inject matrix into cleanup
sed -i 's/  cleanup:/  cleanup:\n    strategy:\n      fail-fast: false\n      matrix: ${{ fromJson(needs.preflight.outputs.nodes_matrix) }}/g' $FILE
sed -i 's/name: Post-deploy Cleanup/name: Cleanup (\${{ matrix.name }})/g' $FILE

# Now replace 'needs.preflight.outputs.vps_host' with 'matrix.host' inside those jobs EXCEPT preflight job itself
# Actually, since preflight doesn't use 'needs.preflight.outputs.vps_host' (it generates it), we can replace globally!
sed -i 's/needs.preflight.outputs.vps_host/matrix.host/g' $FILE
sed -i 's/needs.preflight.outputs.vps_user/matrix.user/g' $FILE
sed -i 's/needs.preflight.outputs.project_dir/matrix.project_dir/g' $FILE
sed -i 's/needs.preflight.outputs.backup_dir/matrix.backup_dir/g' $FILE
sed -i 's/needs.preflight.outputs.log_dir/matrix.log_dir/g' $FILE

echo "Done editing CD pipeline."
