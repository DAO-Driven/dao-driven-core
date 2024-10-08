// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IAllo} from "../../lib/allo-v2/interfaces/IAllo.sol";
import {IStrategyFactory} from "../../lib/allo-v2/interfaces/IStrategyFactory.sol";
import {BountyStrategy} from "./BountyStrategy.sol";
import {IHats} from "../../lib/hats/IHats.sol";
import {SafeTransferLib} from "../../lib/solady/src/utils/SafeTransferLib.sol";
import {Errors} from "../../lib/allo-v2/libraries/Errors.sol";

import "../../lib/allo-v2/libraries/Structs.sol";
import "../../lib/allo-v2/interfaces/IRegistry.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
// import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

contract Manager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, Errors {
    enum ProjectType {
        None,
        Bounty,
        CrowdFunding
    }

    /// @notice Struct containing all information relevant to a project.
    struct ProjectInformation {
        address token;
        address executor;
        address[] suppliers;
        SuppliersById suppliersById;
        ProjectSupply supply;
        uint256 poolId;
        address strategy;
        ProjectType projectType;
    }

    /// @notice Interface to interact with the Registry contract.
    IRegistry registry;

    /// @notice Interface to interact with the Allo contract.
    IAllo allo;

    /// @notice Address of the strategy contract.
    address strategy;

    /// @notice Interface to interact with the Strategy Factory contract.
    IStrategyFactory strategyFactory;

    /// @notice Interface to interact with the Hats contract.
    IHats public hatsContract;

    /// @notice ID of the manager's hat in the Hats contract.
    uint256 managerHatID;

    /// @notice Address of the Hats contract.
    address hatsContractAddress;

    /// @notice Voting Threshold Percentage.
    uint8 thresholdPercentage;

    /// ================================
    /// ========== Storage =============
    /// ================================

    mapping(bytes32 => ProjectInformation) projects;

    bool private initialized;

    /// ===============================
    /// ========== Events =============
    /// ===============================

    /// @notice Emitted when a project receives funding.
    /// @param projectId The ID of the project that was funded.
    /// @param amount The amount of funds the project received.
    event ProjectFunded(bytes32 indexed projectId, uint256 amount);

    /// @notice Emitted when a pool is created for a project.
    /// @param projectId The ID of the project for which the pool was created.
    /// @param poolId The ID of the newly created pool.
    event ProjectPoolCreated(bytes32 projectId, uint256 poolId);

    event ProjectRegistered(bytes32 profileId, uint256 nonce);

    event ProjectNeedsUpdated(bytes32 indexed projectId, uint256 newNeeds);

    function initialize(
        address _alloAddress,
        address _strategy,
        address _strategyFactory,
        address _hatsContractAddress,
        uint256 _managerHatID
    ) public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        allo = IAllo(_alloAddress);
        strategy = _strategy;
        strategyFactory = IStrategyFactory(_strategyFactory);
        hatsContractAddress = _hatsContractAddress;
        hatsContract = IHats(_hatsContractAddress);
        managerHatID = _managerHatID;
        address registryAddress = address(allo.getRegistry());
        registry = IRegistry(registryAddress);
        thresholdPercentage = 70; // Default value, adjust as needed
    }

    /// @notice Retrieves the profile of a project from the registry.
    /// @param _projectId The ID of the project.
    /// @return IRegistry.Profile The profile of the specified project.
    function getProfile(bytes32 _projectId) public view returns (IRegistry.Profile memory) {
        return registry.getProfileById(_projectId);
    }

    /// @notice Retrieves the pool ID associated with a project.
    /// @param _projectId The ID of the project.
    /// @return uint256 The pool ID of the specified project.
    function getProjectPool(bytes32 _projectId) public view returns (uint256) {
        return projects[_projectId].poolId;
    }

    /// @notice Retrieves a list of supplier addresses for a project.
    /// @param _projectId The ID of the project.
    /// @return address[] An array of addresses of the suppliers for the specified project.
    function getProjectSuppliers(bytes32 _projectId) public view returns (address[] memory) {
        return projects[_projectId].suppliers;
    }

    /// @notice Retrieves the supply amount provided by a specific supplier for a project.
    /// @param _projectId The ID of the project.
    /// @param _supplier The address of the supplier.
    /// @return uint256 The amount supplied by the specified supplier for the project.
    function getProjectSupplierById(bytes32 _projectId, address _supplier) public view returns (uint256) {
        return projects[_projectId].suppliersById.supplyById[_supplier];
    }

    /// @notice Retrieves the executor address for a project.
    /// @param _projectId The ID of the project.
    /// @return address The address of the executor for the specified project.
    function getProjectExecutor(bytes32 _projectId) public view returns (address) {
        return projects[_projectId].executor;
    }

    /// @notice Retrieves the strategy address for a project.
    /// @param _projectId The ID of the project.
    /// @return address The address of the strategy associated with the specified project.
    function getProjectStrategy(bytes32 _projectId) public view returns (address) {
        return projects[_projectId].strategy;
    }

    /**
     * @notice Retrieves the supply details of a specific project.
     * @param _projectId The ID of the project for which to get the supply details.
     * @return ProjectSupply A struct containing the project's supply details, including total need and amount supplied.
     */
    function getProjectSupply(bytes32 _projectId) public view returns (ProjectSupply memory) {
        return projects[_projectId].supply;
    }

    /// @notice Sets a new Allo contract address
    /// @dev Only callable by the contract owner
    /// @param newAlloAddress The address of the new Allo contract
    function setAlloAddress(address newAlloAddress) external onlyOwner {
        allo = IAllo(newAlloAddress);
    }

    /// @notice Sets a new Strategy contract address
    /// @dev Only callable by the contract owner
    /// @param newStrategy The address of the new Strategy contract
    function setStrategyAddress(address newStrategy) external onlyOwner {
        strategy = newStrategy;
    }

    /// @notice Sets a new Strategy Factory contract address
    /// @dev Only callable by the contract owner
    /// @param newStrategyFactory The address of the new Strategy Factory contract
    function setStrategyFactoryAddress(address newStrategyFactory) external onlyOwner {
        strategyFactory = IStrategyFactory(newStrategyFactory);
    }

    /// @notice Sets a new Hats contract address
    /// @dev Only callable by the contract owner
    /// @param newHatsContractAddress The address of the new Hats contract
    function setHatsContractAddress(address newHatsContractAddress) external onlyOwner {
        hatsContractAddress = newHatsContractAddress;
        hatsContract = IHats(newHatsContractAddress);
    }

    /// @notice Sets a new Manager Hat ID
    /// @dev Only callable by the contract owner
    /// @param newManagerHatID The new Manager Hat ID
    function setManagerHatID(uint256 newManagerHatID) external onlyOwner {
        managerHatID = newManagerHatID;
    }

    /// @notice Sets the threshold percentage for a specific profile.
    /// @param _newPercentage The new threshold percentage to be set.
    /// @dev Requires the sender to be the owner of the profile and the percentage to be between 1 and 100.
    function setThresholdPercentage(uint8 _newPercentage) external onlyOwner {
        require(_newPercentage > 0, "Percentage must be greater than zero");
        require(_newPercentage <= 100, "Invalid percentage");
        thresholdPercentage = _newPercentage;
    }

    /// @notice Registers a new project and creates its profile.
    /// @dev Creates a new project profile in the registry and initializes its supply details.
    /// @param _token The token of the project.
    /// @param _needs The total amount needed for the project.
    /// @param _nonce A unique nonce for profile creation to ensure uniqueness.
    /// @param _name The name of the project.
    /// @param _metadata Metadata associated with the project.
    function registerProject(
        ProjectType _type,
        address _token,
        uint256 _needs,
        uint256 _nonce,
        string memory _name,
        Metadata memory _metadata
    ) external returns (bytes32) {
        address[] memory members = new address[](2);
        members[0] = msg.sender;
        members[1] = address(this);

        bytes32 profileId = registry.createProfile(_nonce, _name, _metadata, address(this), members);

        projects[profileId].token = _token;
        projects[profileId].supply.need = allo.getPercentFee() + _needs;
        projects[profileId].projectType = _type;
        if (_type == ProjectType.CrowdFunding) {
            projects[profileId].executor = msg.sender;
        }

        emit ProjectRegistered(profileId, _nonce);

        return profileId;
    }

    /**
     * @notice Supplies funds to a specific project.
     * @dev This function requires that the project exists and is not fully funded.
     *      The supplied amount must be non-zero and equal to the sent value. If the supplied amount meets or exceeds
     *      the project's need, it triggers the creation of supplier and executor hats, and initializes a new pool
     *      with a custom strategy. Emits a ProjectFunded event and, if funding is complete, a ProjectPoolCreated event.
     * @param _projectId The ID of the project to supply funds to.
     * @param _amount The amount of funds to supply.
     */
    function supplyProject(bytes32 _projectId, uint256 _amount) external payable nonReentrant {
        if ((projects[_projectId].supply.has + _amount) > projects[_projectId].supply.need) {
            revert AMOUNT_IS_BIGGER_THAN_DECLARED_NEEDEDS();
        }
        require(_projectExists(_projectId), "Project does not exist");

        if (_amount == 0 && _amount <= projects[_projectId].supply.need) revert INVALID_AMOUNT();

        if (projects[_projectId].poolId != 0) revert PROJECT_HAS_POOL();

        if (projects[_projectId].executor == msg.sender && projects[_projectId].projectType == ProjectType.CrowdFunding)
        {
            revert EXECUTOR_IS_NOT_ALLOWED_TO_SUPPLY();
        }

        SafeTransferLib.safeTransferFrom(projects[_projectId].token, address(msg.sender), address(this), _amount);

        projects[_projectId].supply.has += _amount;

        if (projects[_projectId].suppliersById.supplyById[msg.sender] == 0) {
            projects[_projectId].suppliers.push(msg.sender);
        }

        projects[_projectId].suppliersById.supplyById[msg.sender] += _amount;

        emit ProjectFunded(_projectId, _amount);

        if (projects[_projectId].supply.has >= projects[_projectId].supply.need) {
            BountyStrategy.SupplierPower[] memory suppliers = _extractSupliers(_projectId);
            address[] memory managers = new address[](suppliers.length);

            for (uint256 i = 0; i < suppliers.length; i++) {
                managers[i] = (suppliers[i].supplierId);
            }

            projects[_projectId].strategy = strategyFactory.createStrategy(strategy);

            uint256 strategyHat = _createAndMintStrategyHat("Strategy", projects[_projectId].strategy, "strategyImage");

            bytes memory encodedInitData = abi.encode(
                BountyStrategy.InitializeData({
                    strategyHat: strategyHat,
                    projectSuppliers: suppliers,
                    hatsContractAddress: hatsContractAddress,
                    maxRecipients: 1
                })
            );

            uint256 pool = allo.createPoolWithCustomStrategy(
                _projectId,
                projects[_projectId].strategy,
                encodedInitData,
                projects[_projectId].token,
                0,
                Metadata({
                    protocol: 1,
                    pointer: "https://github.com/alexandr-masl/web3-crowdfunding-on-allo-V2/blob/main/contracts/BountyStrategy.sol"
                }),
                managers
            );

            IERC20 token = IERC20(projects[_projectId].token);

            require(
                token.balanceOf(address(this)) >= projects[_projectId].supply.need,
                "Insufficient token balance in contract"
            );

            token.approve(address(allo), projects[_projectId].supply.need);

            allo.fundPool(pool, projects[_projectId].supply.need);

            projects[_projectId].poolId = pool;

            emit ProjectPoolCreated(_projectId, pool);
        }
    }

    /**
     * @notice Revokes the supply contributed by the sender to a specific project.
     * @dev Requires that the project exists and the sender has previously supplied funds to it.
     *      The function updates the project's supply details and removes the sender from the list of suppliers.
     *      It also refunds the contributed amount to the sender.
     * @param _projectId The ID of the project from which to revoke the supply.
     */
    function revokeProjectSupply(bytes32 _projectId) external nonReentrant {
        require(_projectExists(_projectId), "Project does not exist");

        if (projects[_projectId].poolId != 0) revert PROJECT_HAS_POOL();

        uint256 amount = projects[_projectId].suppliersById.supplyById[msg.sender];
        require(amount > 0, "SUPPLY NOT FOUND");

        delete projects[_projectId].suppliersById.supplyById[msg.sender];

        projects[_projectId].supply.has -= amount;

        address[] memory updatedSuppliers = new address[](projects[_projectId].suppliers.length - 1);
        uint256 j = 0;

        for (uint256 i = 0; i < projects[_projectId].suppliers.length; i++) {
            if (projects[_projectId].suppliers[i] != msg.sender) {
                updatedSuppliers[j] = projects[_projectId].suppliers[i];
                j++;
            }
        }

        projects[_projectId].suppliers = updatedSuppliers;

        SafeTransferLib.safeTransfer(projects[_projectId].token, msg.sender, amount);
    }

    /**
     * @notice Extracts and returns the power of all suppliers for a given project.
     * @dev Iterates through the list of suppliers for the project and compiles their power into an array.
     * @param _projectId The ID of the project for which to extract supplier powers.
     * @return SupplierPower[] An array of SupplierPower structs, each representing a supplier's power for the project.
     */
    function _extractSupliers(bytes32 _projectId) internal view returns (BountyStrategy.SupplierPower[] memory) {
        BountyStrategy.SupplierPower[] memory suppliersPower =
            new BountyStrategy.SupplierPower[](projects[_projectId].suppliers.length);

        for (uint256 i = 0; i < projects[_projectId].suppliers.length; i++) {
            address supplierId = projects[_projectId].suppliers[i];
            uint256 supplierPower = projects[_projectId].suppliersById.supplyById[supplierId];

            suppliersPower[i] = BountyStrategy.SupplierPower(supplierId, uint256(supplierPower));
        }

        return suppliersPower;
    }

    /**
     * @notice Checks if a project with the given profile ID exists.
     * @dev A project exists if its profile has an owner address that is not the zero address.
     * @param _profileId The profile ID of the project to check.
     * @return bool Returns 'true' if the project exists, 'false' otherwise.
     */
    function _projectExists(bytes32 _profileId) private view returns (bool) {
        IRegistry.Profile memory profile = registry.getProfileById(_profileId);
        return profile.owner != address(0);
    }

    function _createAndMintStrategyHat(string memory _hatName, address _hatWearer, string memory _imageURI)
        private
        returns (uint256 hatId)
    {
        hatId = hatsContract.createHat(managerHatID, _hatName, 1, address(this), address(this), true, _imageURI);

        bool isEligible = hatsContract.isEligible(_hatWearer, hatId);

        require(isEligible, "Wearer not eligible");

        hatsContract.mintHat(hatId, _hatWearer);

        return hatId;
    }

    // function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice This contract should be able to receive native token
    receive() external payable {}
}
