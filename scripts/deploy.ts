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

// ✅ Auth Contract has been deployed with the address: 0x20fcdda8e3f1f672161768a416561980052a78086f22ad119374132d1377bd9
// ✅ Validator Contract has been deployed with the address: 0x42477a8d5d8ad77c9919b2e79ffe294b74d953a49ebe968fd16da200f4b9010
// ✅ Campaign Contract has been deployed with the address: 0x71d529cf3723ea0324573f17c3e5a5689550701d1ddc875a4586fe66c5af7d
// ✅ Validator Report Contract has been deployed with the address: 0x36c408de5f5128dc80bf2a8429ba3a0bcab1c45fd2012481592865fbfdde876
// ✅ Progress Tracking Contract has been deployed with the address: 0x5683e443f459d4d195bfaf16acf1a4eae96fff67f891d06425e60a5583f5acb