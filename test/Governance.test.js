const { expect } = require("chai");
const { ethers } = require("hardhat");

// Helper to simulate loadFixture
let fixtureData;
async function getFixture(deployFn) {
    if (!fixtureData) {
        fixtureData = await deployFn();
    }
    return fixtureData;
}

// Low-level EVM helpers
async function mine(blocks) {
    for (let i = 0; i < blocks; i++) {
        await ethers.provider.send("evm_mine", []);
    }
}

async function increaseTime(seconds) {
    await ethers.provider.send("evm_increaseTime", [seconds]);
    await ethers.provider.send("evm_mine", []);
}

describe("CryptoVentures DAO Governance", function () {
    async function deployGovernanceFixture() {
        const [deployer, whale, fish1, fish2, beneficiary] = await ethers.getSigners();

        const Treasury = await ethers.getContractFactory("Treasury");
        const treasury = await Treasury.deploy();
        await treasury.waitForDeployment();
        const treasuryAddress = await treasury.getAddress();

        const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
        const token = await GovernanceToken.deploy("CryptoVentures", "CVT");
        await token.waitForDeployment();
        const tokenAddress = await token.getAddress();

        await token.setTreasury(treasuryAddress);
        const WITHDRAWER_ROLE = await treasury.WITHDRAWER_ROLE();
        await treasury.grantRole(WITHDRAWER_ROLE, tokenAddress);

        const minDelay = 3600;
        const TimeLock = await ethers.getContractFactory("TimeLock");
        const timelock = await TimeLock.deploy(minDelay, [], [], deployer.address);
        await timelock.waitForDeployment();
        const timelockAddress = await timelock.getAddress();

        const Governance = await ethers.getContractFactory("CryptoVenturesGovernance");
        const governance = await Governance.deploy(tokenAddress, timelockAddress);
        await governance.waitForDeployment();
        const governanceAddress = await governance.getAddress();

        await treasury.grantRole(await treasury.EXECUTOR_ROLE(), timelockAddress);
        await timelock.grantRole(await timelock.PROPOSER_ROLE(), governanceAddress);
        await timelock.grantRole(await timelock.EXECUTOR_ROLE(), ethers.ZeroAddress);

        return {
            treasury, token, timelock, governance,
            deployer, whale, fish1, fish2, beneficiary
        };
    }

    // We reset state manually for simplicity in this specific test environment
    let state;
    beforeEach(async () => {
        state = await deployGovernanceFixture();
    });

    describe("Governance Token & Staking", function () {
        it("Should mint tokens 1:1 for ETH deposits", async function () {
            const { token, fish1 } = state;
            const amount = ethers.parseEther("10");
            await token.connect(fish1).deposit({ value: amount });
            expect(await token.balanceOf(fish1.address)).to.equal(amount);
        });

        it("Should allow withdrawals and return ETH from Treasury", async function () {
            const { token, fish1 } = state;
            const amount = ethers.parseEther("10");
            await token.connect(fish1).deposit({ value: amount });

            const balanceBefore = await ethers.provider.getBalance(fish1.address);
            await token.connect(fish1).withdraw(amount);
            const balanceAfter = await ethers.provider.getBalance(fish1.address);

            expect(await token.balanceOf(fish1.address)).to.equal(0n);
            expect(balanceAfter > balanceBefore).to.be.true;
        });
    });

    describe("Quadratic Voting (Anti-Whale)", function () {
        it("Should mitigate whale dominance", async function () {
            const { token, governance, whale, fish1 } = state;

            await token.connect(whale).deposit({ value: ethers.parseEther("1000") });
            await token.connect(whale).delegate(whale.address);

            await token.connect(fish1).deposit({ value: ethers.parseEther("10") });
            await token.connect(fish1).delegate(fish1.address);

            await mine(1);
            const block = await ethers.provider.getBlock("latest");
            const timepoint = block.timestamp - 1; // Look back slightly to ensure snapshot logic

            const whaleVotes = await governance.getVotes(whale.address, timepoint);
            const fishVotes = await governance.getVotes(fish1.address, timepoint);

            // Whale: 1000e18 -> sqrt is 31.622e9
            // Fish: 10e18 -> sqrt is 3.162e9
            // Ratio in power: 10:1

            expect(fishVotes > 0n).to.be.true;
            expect(whaleVotes / fishVotes).to.equal(10n);
        });
    });

    describe("Multi-Tier Proposals & Quorum", function () {
        it("Should succeed with lower Operational quorum", async function () {
            const { token, governance, treasury, fish1, beneficiary } = state;

            await token.connect(fish1).deposit({ value: ethers.parseEther("2500") });
            await token.connect(fish1).delegate(fish1.address);


            const calldata = treasury.interface.encodeFunctionData("releaseFunds", [beneficiary.address, 100n, 2]);
            const tx = await governance.connect(fish1)["propose(address[],uint256[],bytes[],string,uint8)"](
                [await treasury.getAddress()],
                [0n],
                [calldata],
                "Operational Funding",
                2 // Operational
            );
            const receipt = await tx.wait();
            const pId = receipt.logs[0].args[0];

            // Wait for voting delay (1 day)
            await increaseTime(1 * 24 * 60 * 60 + 1);

            await governance.connect(fish1).castVote(pId, 1);

            await increaseTime(7 * 24 * 60 * 60 + 1);
            expect(await governance.state(pId)).to.equal(4n); // Succeeded
        });
    });

    describe("Tiered Timelock Delays", function () {
        it("Should enforce dynamic delays per tier", async function () {
            const { token, governance, treasury, fish1, beneficiary } = state;

            await token.connect(fish1).deposit({ value: ethers.parseEther("100") });
            await token.connect(fish1).delegate(fish1.address);

            // HC Proposal
            const cd1 = treasury.interface.encodeFunctionData("releaseFunds", [beneficiary.address, 100n, 0]);
            const t1 = await governance.connect(fish1)["propose(address[],uint256[],bytes[],string,uint8)"](
                [await treasury.getAddress()],
                [0n],
                [cd1],
                "HC Proposal",
                0
            );
            const pId1 = (await t1.wait()).logs[0].args[0];

            // Op Proposal
            const cd2 = treasury.interface.encodeFunctionData("releaseFunds", [beneficiary.address, 100n, 2]);
            const t2 = await governance.connect(fish1)["propose(address[],uint256[],bytes[],string,uint8)"](
                [await treasury.getAddress()],
                [0n],
                [cd2],
                "Op Proposal",
                2
            );
            const pId2 = (await t2.wait()).logs[0].args[0];

            // Wait for voting delay (1 day)
            await increaseTime(1 * 24 * 60 * 60 + 1);

            await mine(2);
            await governance.connect(fish1).castVote(pId1, 1);
            await governance.connect(fish1).castVote(pId2, 1);
            await increaseTime(7 * 24 * 60 * 60 + 1);

            await governance.queue([await treasury.getAddress()], [0], [cd1], ethers.id("HC Proposal"));
            await governance.queue([await treasury.getAddress()], [0], [cd2], ethers.id("Op Proposal"));


            const block = await ethers.provider.getBlock("latest");
            const now = BigInt(block.timestamp);
            const eta1 = await governance.proposalEta(pId1);
            const eta2 = await governance.proposalEta(pId2);

            // Manual comparison for BigInts
            const diff1 = eta1 > now ? eta1 - now : now - eta1;
            const diff2 = eta2 > now ? eta2 - now : now - eta2;

            const target1 = BigInt(2 * 24 * 60 * 60);
            const target2 = BigInt(6 * 60 * 60);
            const tolerance = 60n;

            expect(diff1 >= target1 - tolerance && diff1 <= target1 + tolerance).to.be.true;
            expect(diff2 >= target2 - tolerance && diff2 <= target2 + tolerance).to.be.true;
        });
    });
});
