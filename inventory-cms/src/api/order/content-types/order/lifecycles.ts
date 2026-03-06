export default {
    afterCreate(event: any) {
        const { result } = event;
        // Broadcast via the realtime service
        strapi.service('api::realtime.realtime').publishOrderUpdate(result, 'create');
    },

    afterUpdate(event: any) {
        const { result } = event;
        strapi.service('api::realtime.realtime').publishOrderUpdate(result, 'update');
    },

    afterDelete(event: any) {
        const { result } = event;
        strapi.service('api::realtime.realtime').publishOrderUpdate(result, 'delete');
    }
};
