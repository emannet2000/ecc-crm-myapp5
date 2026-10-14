'use strict';
const integrations = ['email', 'whatsapp', 'payments', 'ai'];
function acceptanceOptions(env, argv = []) {
 if (env.ECC_ACCEPTANCE_STRICT !== undefined && !['true', 'false'].includes(env.ECC_ACCEPTANCE_STRICT)) throw new Error('ECC_ACCEPTANCE_STRICT must be true or false');
 const strict = env.ECC_ACCEPTANCE_STRICT === 'true' || argv.includes('--strict');
 const required = env.ECC_ACCEPTANCE_REQUIRED === undefined ? integrations : env.ECC_ACCEPTANCE_REQUIRED.split(',').map(name => name.trim());
 if (!required.length || required.some(name => !integrations.includes(name)) || new Set(required).size !== required.length) throw new Error('Choose distinct required integrations from email, whatsapp, payments, ai');
 return {strict, required};
}
function evaluateAcceptance(results, {strict, required}) {
 const incomplete = required.flatMap(integration => {
  const rows = results.filter(row => row.integration === integration);
  if (rows.length !== 1) return [{integration, status: rows.length ? 'duplicate_results' : 'missing'}];
  return rows[0].status === 'passed' ? [] : [{integration, status: rows[0].status || 'missing_status'}];
 });
 const failed = results.some(row => row.status === 'failed');
 return {mode: strict ? 'strict' : 'assessment', requiredIntegrations: required,
  complete: !failed && incomplete.length === 0, state: failed ? 'failed' : incomplete.length ? 'incomplete' : 'passed', incomplete,
  exitCode: failed || strict && incomplete.length ? 1 : 0};
}
module.exports = {acceptanceOptions, evaluateAcceptance};
