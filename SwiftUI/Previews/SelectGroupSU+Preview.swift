//
//  SelectGroupSU+Preview.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/18/25.
//
func mockGroup(id: Int32, name: String) -> Group {
    let context = PersistenceController.preview.container.viewContext
    let group = Group(context: context)
    group.groupId = Int16(id)
    group.groupName = name
    return group
}
