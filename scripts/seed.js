const { ethers } = require("hardhat");

async function main() {
    const [deployer, user1, user2] = await ethers.getSigners();

    // Note: For seeding, we assume the contracts were just deployed to a local node
    // In a real scenario, we'd pull addresses from a deployments file or environment.
    // We'll redeploy here for a clean demonstration on the local hardhat network.

    console.log("Seeding data...");

    // Deploying fresh for the seed demonstration
    const Treasury = await ethers.getContractFactory("Treasury");
    const treasury = await Treasury.deploy();
    const tokenFactory = await ethers.getContractFactory("GovernanceToken");
    const token = await tokenFactory.deploy("CryptoVentures", "CVT");
    const timelockFactory = await ethers.getContractFactory("TimeLock");
    const timelock = await timelockFactory.deploy(3600, [], [], deployer.address);
    const govFactory = await ethers.getContractFactory("CryptoVenturesGovernance");
    const governance = await govFactory.deploy(await token.getAddress(), await timelock.getAddress());

    // Setup roles as in deploy script
    await token.setTreasury(await treasury.getAddress());
    await treasury.grantRole(await treasury.WITHDRAWER_ROLE(), await token.getAddress());
    await treasury.grantRole(await treasury.EXECUTOR_ROLE(), await timelock.getAddress());
    await timelock.grantRole(await timelock.PROPOSER_ROLE(), await governance.getAddress());
    await timelock.grantRole(await timelock.EXECUTOR_ROLE(), ethers.ZeroAddress);

    // 1. Users Stake ETH to get Voting Power
    console.log("Users staking ETH...");
    await token.connect(user1).deposit({ value: ethers.parseEther("100") });
    await token.connect(user2).deposit({ value: ethers.parseEther("500") });

    await token.connect(user1).delegate(user1.address);
    await token.connect(user2).delegate(user2.address);
    console.log("Staking and delegation complete.");

    // 2. Create sample proposals
    console.log("Creating sample proposals...");
    const devFunding = ethers.parseEther("4"); // Within 5 ETH Op Limit
    const calldata = treasury.interface.encodeFunctionData("releaseFunds", [user1.address, devFunding, 2]); // Operational

    const tx = await governance.connect(user2)["propose(address[],uint256[],bytes[],string,uint8)"](
        [await treasury.getAddress()],
        [0],
        [calldata],
        "Seed: Operational funding for dev tools",
        2 // Operational
    );
    const receipt = await tx.wait();
    console.log("Proposal created! ID:", receipt.logs[0].args[0]);

    console.log("Seeding completed successfully.");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
