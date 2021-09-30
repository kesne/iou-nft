import expect from "expect";
import { ethers } from "hardhat";
import { IOweYou } from "../typechain";

const PROMISE = "I promise to do something.";
const NULL_ADDRESS = "0x0000000000000000000000000000000000000000";

// This is the following contract's address on Ropsten:
// https://github.com/ensdomains/reverse-records
const REVERSE_NAMES_CONTRACT_ROPSTEN =
  "0x72c33B247e62d0f1927E8d325d0358b8f9971C68";

describe("IOweYou", () => {
  let iOweYou: IOweYou;
  before(async () => {
    const IOweYou = await ethers.getContractFactory("IOweYou");
    iOweYou = (await IOweYou.deploy(REVERSE_NAMES_CONTRACT_ROPSTEN)) as IOweYou;
    await iOweYou.deployed();
  });

  afterEach(async () => {
    // Re-set the state of token URI:
    await iOweYou.setTokenURIAddress(NULL_ADDRESS);
  });

  it.only("works", async () => {
    const [owner] = await ethers.getSigners();
    console.log(
      await iOweYou.addrToString("0x72CB0Ce0e6716667ea7209C9aD2111690a22F633")
    );
  });

  it("allows for dynamically updating the tokenURI generation", async () => {
    const [, , , , , creator, user] = await ethers.getSigners();
    const createTx = await iOweYou
      .connect(creator)
      .create(user.address, PROMISE);
    await createTx.wait();

    const TestTokenURI = await ethers.getContractFactory("TestTokenURI");
    const testTokenURI = await TestTokenURI.deploy();
    await testTokenURI.deployed();
    await iOweYou.setTokenURIAddress(testTokenURI.address);
    const tokenId = await iOweYou.tokenOfOwnerByIndex(user.address, 0);
    expect(await iOweYou.tokenURI(tokenId)).toEqual(
      `Static Token URI For: ${tokenId}`
    );
  });

  it("should not allow acccessing tokenURI for tokens not yet minted", async () => {
    // Token is not yet minted, accessing the token URI should fail:
    await expect(async () => {
      await iOweYou.tokenURI(999);
    }).rejects.toEqual(expect.anything());
  });

  it("should reject creating an IOU with yourself", async () => {
    await expect(async () => {
      const [owner] = await ethers.getSigners();

      const createTx = await iOweYou.create(owner.address, PROMISE);

      await createTx.wait();
    }).rejects.toMatchObject({
      message: expect.stringContaining("You cannot make an IOU to yourself."),
    });
  });

  it("should support the basic IOU flow", async () => {
    const [creator, receiver, uninvolved] = await ethers.getSigners();

    const iou = await iOweYou.create(receiver.address, PROMISE);
    await iou.wait();

    const creatorBalance = await iOweYou.balanceOf(creator.address);
    const receiverBalance = await iOweYou.balanceOf(receiver.address);

    // We should not mint a NFT on the sender side
    expect(creatorBalance.toNumber()).toBe(0);
    // We should mint an NFT the receiver
    expect(receiverBalance.toNumber()).toBe(1);

    const tokenId = await iOweYou.tokenOfOwnerByIndex(receiver.address, 0);

    // Expect token URI to exist:
    expect(await iOweYou.tokenURI(tokenId)).toEqual(`test://${tokenId}`);

    // Expect the IOU to be the correct shape:
    let iouState = await iOweYou.getIOU(tokenId);
    expect(iouState.owed).toBe(PROMISE);
    expect(iouState.creator).toBe(creator.address);
    expect(iouState.creatorCompleted).toBe(false);
    expect(iouState.receiverCompleted).toBe(false);

    // Complete it from the creator side:
    const completeTx = await iOweYou.complete(tokenId);
    await completeTx.wait();
    iouState = await iOweYou.getIOU(tokenId);
    expect(iouState.creatorCompleted).toBe(true);
    expect(iouState.receiverCompleted).toBe(false);

    // Attempt to complete it as an uninvolved party:
    await expect(async () => {
      await iOweYou.connect(uninvolved).complete(tokenId);
    }).rejects.toMatchObject({
      message: expect.stringContaining("You can only complete your own IOU"),
    });

    // Complete it as the receiver
    const receiverCompleteTx = await iOweYou
      .connect(receiver)
      .complete(tokenId);
    await receiverCompleteTx.wait();

    // Attempting should get it should throw, as the token has been burnt:
    await expect(async () => {
      await iOweYou.getIOU(tokenId);
    }).rejects.toMatchObject({
      message: expect.stringContaining("IOU does not exist."),
    });

    // Should be burned:
    expect((await iOweYou.balanceOf(receiver.address)).toNumber()).toBe(0);
  });

  it("should be creator enumerable", async () => {
    const [creator, receiver1, receiver2] = await ethers.getSigners();

    async function checkBalance(signer: { address: string }, count: number) {
      return expect(
        (await iOweYou.createdBalanceOf(signer.address)).toNumber()
      ).toBe(count);
    }

    // Everyone should start with no tokens created:
    await checkBalance(creator, 0);
    await checkBalance(receiver1, 0);
    await checkBalance(receiver2, 0);

    // We'll create multiple tokens, to different receivers:
    const tokensToCreate = [
      receiver1,
      receiver1,
      receiver1,
      receiver2,
      receiver2,
    ];

    await Promise.all(
      tokensToCreate.map(async () => {
        await (await iOweYou.create(receiver1.address, PROMISE)).wait();
      })
    );

    await checkBalance(creator, tokensToCreate.length);
    await checkBalance(receiver1, 0);
    await checkBalance(receiver2, 0);

    // Get the tokens IDs:
    const tokenIds: number[] = [];
    for (
      let i = 0;
      i < (await iOweYou.createdBalanceOf(creator.address)).toNumber();
      i += 1
    ) {
      tokenIds.push(
        (await iOweYou.tokenOfCreatorByIndex(creator.address, i)).toNumber()
      );
    }

    expect(tokenIds).toHaveLength(tokensToCreate.length);

    // Progressively burn the tokens:
    let expectedTokenCount = tokensToCreate.length;
    for (const tokenId of tokenIds) {
      await iOweYou.connect(creator).complete(tokenId);
      // Also mark it as complete for the other users. We blindly do this for both receivers
      // to avoid extra bookkeeping, and just expect one of them to resolve:
      await Promise.any([
        iOweYou.connect(receiver1).complete(tokenId),
        iOweYou.connect(receiver2).complete(tokenId),
      ]);

      // We expect one less token now:
      expectedTokenCount -= 1;
      await checkBalance(creator, expectedTokenCount);
    }
  });
});
