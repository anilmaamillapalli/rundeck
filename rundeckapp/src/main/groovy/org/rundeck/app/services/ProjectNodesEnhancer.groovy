/*
 * Copyright 2019 Rundeck, Inc. (http://rundeck.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.rundeck.app.services

import com.dtolabs.rundeck.core.common.*
import groovy.transform.CompileStatic

@CompileStatic
class ProjectNodesEnhancer implements IProjectNodes {
    @Delegate IProjectNodes projectNodes

    String project
    List<TypedNodeEnhancerPlugin> plugins = []
    long loadedTime

    @Override
    INodeSet getNodeSet() {
        def nodeset = projectNodes.getNodeSet()
        def newNodes = new NodeSetImpl()
        nodeset.nodeNames.each { String node ->
            INodeEntry origNode = nodeset.getNode(node)
            Map<String, String> attrs = new HashMap<>()
            attrs.putAll origNode.attributes
            plugins.each { plugin ->
                INodeEntry newNode = new NodeEntryImpl(node)
                newNode.attributes.putAll attrs
                def node1 = plugin.updateNode(project, newNode, plugin.type)
                if (node1 != null) {
                    attrs.putAll(node1.attributes)
                }
            }
            INodeEntry newNode = new NodeEntryImpl(node)
            newNode.attributes.putAll attrs
            newNodes.putNode(newNode)
        }
        return newNodes
    }

    IProjectNodes withProjectNodes(IProjectNodes projectNodes) {
        if (!plugins) {
            return projectNodes
        }
        return new ProjectNodesEnhancer(
                projectNodes: projectNodes,
                plugins: plugins,
                project: project,
                loadedTime: loadedTime
        )
    }
}
