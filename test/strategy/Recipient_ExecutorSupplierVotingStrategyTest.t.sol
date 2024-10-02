// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Manager} from "../../src/contracts/Manager.sol";
import {MockERC20} from "../../src/contracts/mocks/MockERC20.sol";
import {Metadata} from "../../src/contracts/libraries/Metadata.sol";
import {IHats} from "../../src/contracts/interfaces/Hats/IHats.sol";
import {ExecutorSupplierVotingStrategy} from "../../src/contracts/ExecutorSupplierVotingStrategy.sol";
import {StrategyFactory} from "../../src/contracts/libraries/StrategyFactory.sol";
import {IStrategy} from "../../src/contracts/interfaces/IStrategy.sol";
import {Errors} from "../../src/contracts/libraries/Errors.sol";

contract ExecutorSupplierVotingStrategyTest is Test {
    Manager public manager;
    address mainHat = 0x01Ae8d6d0F137CF946e354eA707B698E8CaE6485;
    uint256 topHatId = 0x0000005200010000000000000000000000000000000000000000000000000000;
    address projectExecutor = address(0x456);
    address projectExecutor2 = address(0x454);
    address projectManager1 = address(0x459);
    address projectManager2 = address(0x458);
    address projectManager3 = address(0x457);
    address unAuthorized = address(0x455);
    ExecutorSupplierVotingStrategy strategy;
    StrategyFactory strategyFactory;
    address hatsContractAddress = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
    uint256 managerHatID = 0x0000005200010000000000000000000000000000000000000000000000000000;

    bytes32 profileId;
    MockERC20 projectToken;

    event ProjectRegistered(uint256 indexed profileId, uint256 nonce);

    function setUp() public {
        projectToken = new MockERC20("TOKEN", "TKN", 18);

        strategyFactory = new StrategyFactory();

        strategy = new ExecutorSupplierVotingStrategy(
            0x1133eA7Af70876e64665ecD07C0A0476d09465a1, "ExecutorSupplierVotingStrategy"
        );

        manager = new Manager();

        manager.initialize(
            0x1133eA7Af70876e64665ecD07C0A0476d09465a1,
            address(strategy),
            address(strategyFactory),
            hatsContractAddress,
            managerHatID
        );

        projectToken.mint(address(projectManager1), 2000e18);
        projectToken.mint(address(projectManager2), 2000e18);
        projectToken.mint(address(projectManager3), 2000e18);

        IHats hatsProtocol = IHats(hatsContractAddress);

        vm.prank(mainHat);
        hatsProtocol.transferHat(topHatId, mainHat, address(manager));

        vm.prank(projectManager1);
        profileId = manager.registerProject(
            address(projectToken),
            1e18,
            777777,
            "ExecutorSupplierVotingStrategyTest",
            Metadata({protocol: 1, pointer: ""})
        );
    }

    function test_UnAuthorizedReviewRecipient() external {
        vm.startPrank(projectManager1);

        projectToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18);

        vm.stopPrank();

        address projectStrategy = manager.getProjectStrategy(profileId);
        ExecutorSupplierVotingStrategy strategyContract = ExecutorSupplierVotingStrategy(payable(projectStrategy));

        vm.expectRevert(Errors.SUPPLIER_HAT_WEARING_REQUIRED.selector);

        vm.prank(unAuthorized);
        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Accepted);
    }

    function test_ReviewRecipientByProfileCreator() external {
        vm.startPrank(projectManager1);

        projectToken.approve(address(manager), 100e18);

        manager.supplyProject(profileId, 1e18);

        address projectStrategy = manager.getProjectStrategy(profileId);
        // console.log("::::: projectStrategy:", projectStrategy);

        ExecutorSupplierVotingStrategy strategyContract = ExecutorSupplierVotingStrategy(payable(projectStrategy));

        // address creator = strategyContract.creator();
        // console.log("::::: Strategy Creator:", creator);

        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Accepted);
        // ExecutorSupplierVotingStrategy.Recipient memory firstRecipient = strategyContract.getRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after reviewRecipient (Accepted):", firstRecipient.recipientAddress);

        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Rejected);
        // ExecutorSupplierVotingStrategy.Recipient memory rejectedFirstRecipient = strategyContract.getRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after reviewRecipient (Rejected):", rejectedFirstRecipient.recipientAddress);

        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Accepted);
        // ExecutorSupplierVotingStrategy.Recipient memory reAddedFirstRecipient = strategyContract.getRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after reAddedFirstRecipient (Accepted):", reAddedFirstRecipient.recipientAddress);

        vm.stopPrank();
    }

    function test_ReviewRecipientByProfileManager() external {
        vm.startPrank(projectManager2);

        projectToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18);

        address projectStrategy = manager.getProjectStrategy(profileId);
        ExecutorSupplierVotingStrategy strategyContract = ExecutorSupplierVotingStrategy(payable(projectStrategy));

        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Accepted);
        // (uint256 votesFor, uint256 votesAgainst) = strategyContract.offeredRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after (Accepted) review by Manager | votesFor:", votesFor);
        // console.log(":::::: FirstRecipient after (Accepted) review by Manager | votesAgainst:", votesAgainst);

        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Rejected);
        // (uint256 votesForRejected, uint256 votesAgainstRejected) = strategyContract.offeredRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after (Accepted) review by Manager | votesFor:", votesForRejected);
        // console.log(":::::: FirstRecipient after (Accepted) review by Manager | votesAgainst:", votesAgainstRejected);

        vm.stopPrank();
    }

    function test_RevertDuplicatedReviewRecipientByMultipleProfileManagers() external {
        vm.startPrank(projectManager2);

        projectToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 0.5e18);

        vm.stopPrank();

        vm.startPrank(projectManager3);

        projectToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 0.5e18);

        address projectStrategy = manager.getProjectStrategy(profileId);
        ExecutorSupplierVotingStrategy strategyContract = ExecutorSupplierVotingStrategy(payable(projectStrategy));

        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Accepted);
        // (uint256 votesFor, uint256 votesAgainst) = strategyContract.offeredRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after (Accepted) review by Manager | votesFor:", votesFor);
        // console.log(":::::: FirstRecipient after (Accepted) review by Manager | votesAgainst:", votesAgainst);

        // ExecutorSupplierVotingStrategy.Recipient memory firstRecipient = strategyContract.getRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after reviewRecipient (Accepted):", firstRecipient.recipientAddress);

        vm.expectRevert(Errors.ALREADY_REVIEWED.selector);
        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Rejected);

        vm.stopPrank();

        vm.startPrank(projectManager2);

        strategyContract.reviewRecipient(projectExecutor, IStrategy.Status.Accepted);
        // (uint256 votesForSecondReview, uint256 votesAgainstSecondReview) = strategyContract.offeredRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after second review by Manager | votesFor:", votesForSecondReview);
        // console.log(":::::: FirstRecipient after second review by Manager | votesAgainst:", votesAgainstSecondReview);

        // ExecutorSupplierVotingStrategy.Recipient memory recipientSecondReview = strategyContract.getRecipient(projectExecutor);
        // console.log(":::::: FirstRecipient after reviewRecipient (Accepted):", recipientSecondReview.recipientAddress);

        vm.stopPrank();
    }
}