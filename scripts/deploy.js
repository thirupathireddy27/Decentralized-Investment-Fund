const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // 1. Deploy Treasury
    const Treasury = await ethers.getContractFactory("Treasury");
    const treasury = await Treasury.deploy();
    await treasury.waitForDeployment();
    const treasuryAddress = await treasury.getAddress();
    console.log("Treasury deployed to:", treasuryAddress);

    // 2. Deploy GovernanceToken
    const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
    const token = await GovernanceToken.deploy("CryptoVentures", "CVT");
    await token.waitForDeployment();
    const tokenAddress = await token.getAddress();
    console.log("GovernanceToken deployed to:", tokenAddress);

    // Setup connection
    await token.setTreasury(treasuryAddress);
    const WITHDRAWER_ROLE = await treasury.WITHDRAWER_ROLE();
    await treasury.grantRole(WITHDRAWER_ROLE, tokenAddress);
    console.log("Linked Token to Treasury and granted WITHDRAWER_ROLE");

    // 3. Deploy TimeLock (minDelay 1 hour base)
    const minDelay = 3600;
    const proposers = [];
    const executors = [];

    const TimeLock = await ethers.getContractFactory("TimeLock");
    const timelock = await TimeLock.deploy(minDelay, proposers, executors, deployer.address);
    await timelock.waitForDeployment();
    const timelockAddress = await timelock.getAddress();
    console.log("TimeLock deployed to:", timelockAddress);

    // 4. Deploy Governance
    const Governance = await ethers.getContractFactory("CryptoVenturesGovernance");
    const governance = await Governance.deploy(tokenAddress, timelockAddress);
    await governance.waitForDeployment();
    const governanceAddress = await governance.getAddress();
    console.log("Governance deployed to:", governanceAddress);

    // 5. Finalize Roles
    const EXECUTOR_ROLE_TREASURY = await treasury.EXECUTOR_ROLE();
    await treasury.grantRole(EXECUTOR_ROLE_TREASURY, timelockAddress);
    console.log("Granted EXECUTOR_ROLE on Treasury to TimeLock");

    const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
    await timelock.grantRole(PROPOSER_ROLE, governanceAddress);
    console.log("Granted PROPOSER_ROLE on TimeLock to Governance");

    const EXECUTOR_ROLE_TIMELOCK = await timelock.EXECUTOR_ROLE();
    await timelock.grantRole(EXECUTOR_ROLE_TIMELOCK, ethers.ZeroAddress);
    console.log("Granted EXECUTOR_ROLE on TimeLock to Everyone (Public Execution)");

    console.log("Deployment completed successfully!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
