import axios from 'axios';

interface MasterProductionNature {
    specie: string;
    started_on: string;
    stopped_on: string;
    start_state_of_production: Array<StartStateOfProduction>;
    cycle: string;
    started_on_year: number;
    stopped_on_year: number;
    life_duration: number;
}

interface StartStateOfProduction {
    label: string;
    year: number;
    default: boolean;
}

export class MasterProductionNatureService {
    get(id: number): Promise<MasterProductionNature> {
        return axios.get<MasterProductionNature>(`/backend/master_production_natures/${id}.json`).then((res) => res.data);
    }
}
