import { Account, CallData, Contract, RpcProvider, stark } from "starknet";
import * as dotenv from "dotenv";
import { getCompiledCode } from "./utils";
dotenv.config();

async function main() {
  const provider = new RpcProvider({
    nodeUrl: process.env.RPC_ENDPOINT,
  });

  // initialize existing predeployed account 0
  console.log("ACCOUNT_ADDRESS=", process.env.DEPLOYER_ADDRESS);
  console.log("ACCOUNT_PRIVATE_KEY=", process.env.DEPLOYER_PRIVATE_KEY);
  const privateKey0 = process.env.DEPLOYER_PRIVATE_KEY ?? "";
  const accountAddress0: string = process.env.DEPLOYER_ADDRESS ?? "";
  const account0 = new Account(provider, accountAddress0, privateKey0);
  console.log("Account connected.\n");

  // Declare & deploy contract
  let sierraCode: any, casmCode: any;

  try {
    ({ sierraCode, casmCode } = await getCompiledCode("starkaid_Auth"));
  } catch (error: any) {
    console.log("Failed to read contract files");
    process.exit(1);
  }

  const authCallData = new CallData(sierraCode.abi);
  const authConstructor = authCallData.compile("constructor", {});
  const authDeployResponse = await account0.declareAndDeploy({
    contract: sierraCode,
    casm: casmCode,
    constructorCalldata: authConstructor,
    salt: stark.randomAddress(),
  });

  // Connect the new contract instance :
  const authContract = new Contract(
    sierraCode.abi,
    authDeployResponse.deploy.contract_address,
    provider
  );
  console.log(
    `✅ Auth Contract has been deployed with the address: ${authContract.address}`
  );

  // DEPLOY VALIDATOR CONTRACT
  try {
    ({ sierraCode, casmCode } = await getCompiledCode("starkaid_Validator"));
  } catch (error: any) {
    console.log("Failed to read contract files");
    process.exit(1);
  }

  const validatorCallData = new CallData(sierraCode.abi);
  const validatorConstructor = validatorCallData.compile("constructor", {});
  const validatorDeployResponse = await account0.declareAndDeploy({
    contract: sierraCode,
    casm: casmCode,
    constructorCalldata: validatorConstructor,
    salt: stark.randomAddress(),
  });

  // Connect the new contract instance :
  const validatorContract = new Contract(
    sierraCode.abi,
    validatorDeployResponse.deploy.contract_address,
    provider
  );
  console.log(
    `✅ Validator Contract has been deployed with the address: ${validatorContract.address}`
  );

  // DEPLOY CAMPAIGN CONTRACT
  try {
    ({ sierraCode, casmCode } = await getCompiledCode("starkaid_Campaign"));
  } catch (error: any) {
    console.log("Failed to read contract files");
    process.exit(1);
  }

  const campaignCallData = new CallData(sierraCode.abi);
  const campaignConstructor = campaignCallData.compile("constructor", {
    auth_contract_address: authContract.address,
    validator_contract_address: validatorContract.address,
  });
  const campaignDeployResponse = await account0.declareAndDeploy({
    contract: sierraCode,
    casm: casmCode,
    constructorCalldata: campaignConstructor,
    salt: stark.randomAddress(),
  });

  // Connect the new contract instance :
  const campaignContract = new Contract(
    sierraCode.abi,
    campaignDeployResponse.deploy.contract_address,
    provider
  );
  console.log(
    `✅ Campaign Contract has been deployed with the address: ${campaignContract.address}`
  );

  // DEPLOY VALIDATOR REPORT CONTRACT
  try {
    ({ sierraCode, casmCode } = await getCompiledCode("starkaid_ValidatorReport"));
  } catch (error: any) {
    console.log("Failed to read contract files");
    process.exit(1);
  }

  const validatorReportCallData = new CallData(sierraCode.abi);
  const validatorReportConstructor = validatorReportCallData.compile("constructor", {
    validator_contract_address: validatorContract.address,
  });
  const validatorReportDeployResponse = await account0.declareAndDeploy({
    contract: sierraCode,
    casm: casmCode,
    constructorCalldata: validatorReportConstructor,
    salt: stark.randomAddress(),
  });

  // Connect the new contract instance :
  const validatorReportContract = new Contract(
    sierraCode.abi,
    validatorReportDeployResponse.deploy.contract_address,
    provider
  );
  console.log(
    `✅ Validator Report Contract has been deployed with the address: ${validatorReportContract.address}`
  );

  // DEPLOY PROGRESS TRACKING CONTRACT
  try {
    ({ sierraCode, casmCode } = await getCompiledCode("starkaid_ProgressTracking"));
  } catch (error: any) {
    console.log("Failed to read contract files");
    process.exit(1);
  }

  const progressTrackingCallData = new CallData(sierraCode.abi);
  const progressTrackingConstructor = progressTrackingCallData.compile("constructor", {
    campaign_contract_address: campaignContract.address,
  });
  const progressTrackingDeployResponse = await account0.declareAndDeploy({
    contract: sierraCode,
    casm: casmCode,
    constructorCalldata: progressTrackingConstructor,
    salt: stark.randomAddress(),
  });

  // Connect the new contract instance :
  const progressTrackingContract = new Contract(
    sierraCode.abi,
    progressTrackingDeployResponse.deploy.contract_address,
    provider
  );
  console.log(
    `✅ Progress Tracking Contract has been deployed with the address: ${progressTrackingContract.address}`
  );
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// Remember to run `scarb build` before deploying
// Deploy with `npm run deploy`

// ✅ Auth Contract has been deployed with the address: 0x960940461313db120a76472a35b7fa5cab743125ef5f08c23397e5ac67099e
// ✅ Validator Contract has been deployed with the address: 0x66432f3f7d41e5014b76141b67924cc709961367671290e17dce0eb08162334
// ✅ Campaign Contract has been deployed with the address: 0x775d0322e55c4acf08f569d59a4cc6c0537c2fe531ab4ca5082a8c3be9b2da
// ✅ Validator Report Contract has been deployed with the address: 0x3ae3056c9224b2db375145ea5cb06d5ce2a8221b187645629a56a2c820f9986
// ✅ Progress Tracking Contract has been deployed with the address: 0x76e27857c27b9c44561c3bdc3bd1bb06c827a929f0ff44cea0e2cbbfc33c4f3