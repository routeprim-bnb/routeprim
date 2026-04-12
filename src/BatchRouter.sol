// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IBatchRouter} from "./interfaces/IBatchRouter.sol";
import {IRoutePrim} from "./interfaces/IRoutePrim.sol";

/// @title BatchRouter
/// @notice Executes multiple RoutePrim legs atomically in a single transaction
/// @dev Delegates each leg to the RoutePrim core contract. Because RoutePrim enforces
///      per-signer nonces, each leg must carry a distinct nonce even within the same
///      batch. The entire batch reverts if any single leg fails.
///
///      Typical use-case: a dApp bundles a token swap and a cross-chain bridge
///      initiation into one user-signed transaction via EIP-7702.
contract BatchRouter is IBatchRouter {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The RoutePrim instance this router dispatches to
    IRoutePrim public immutable ROUTE_PRIM;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _routePrim) {
        require(_routePrim != address(0), "BatchRouter: zero address");
        ROUTE_PRIM = IRoutePrim(_routePrim);
    }

    /*//////////////////////////////////////////////////////////////
                            BATCH ROUTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBatchRouter
    function batchRoute(BatchLeg[] calldata legs)
        external
        returns (uint256[] memory amountsOut)
    {
        if (legs.length == 0) revert EmptyBatch();

        amountsOut = new uint256[](legs.length);

        for (uint256 i; i < legs.length; ++i) {
            try ROUTE_PRIM.route(legs[i].route, legs[i].auth) returns (uint256 out) {
                amountsOut[i] = out;
            } catch {
                revert BatchLegFailed(i);
            }
        }

        emit BatchRouted(msg.sender, legs.length, amountsOut);
    }

    /// @inheritdoc IBatchRouter
    /// @dev msg.value must equal the sum of all legs[i].route.amountIn for native legs.
    ///      Excess BNB is NOT refunded — callers must compute the exact total off-chain.
    function batchRouteNative(BatchLeg[] calldata legs)
        external
        payable
        returns (uint256[] memory amountsOut)
    {
        if (legs.length == 0) revert EmptyBatch();

        // Verify that the supplied BNB covers all native legs
        uint256 totalIn;
        for (uint256 i; i < legs.length; ++i) {
            totalIn += legs[i].route.amountIn;
        }
        require(msg.value == totalIn, "BatchRouter: incorrect BNB total");

        amountsOut = new uint256[](legs.length);

        for (uint256 i; i < legs.length; ++i) {
            try ROUTE_PRIM.routeNative{value: legs[i].route.amountIn}(
                legs[i].route,
                legs[i].auth
            ) returns (uint256 out) {
                amountsOut[i] = out;
            } catch {
                revert BatchLegFailed(i);
            }
        }

        emit BatchRouted(msg.sender, legs.length, amountsOut);
    }
}
